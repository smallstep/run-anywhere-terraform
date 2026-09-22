#!/bin/bash
# Headless KOTS install of the Smallstep platform (app slug "smallstep") into
# the EKS cluster that platform built. This is a script, not Terraform, on
# purpose: `kubectl kots install` is a long-running imperative operation with
# its own retry semantics, and wrapping it in a null_resource gives you the
# worst of both worlds — no plan-time diff and no mid-flight visibility
# (Makefile header records the same decision).
#
# The preconditions run cheapest-first and each die() names the exact make
# target that fixes it. They exist because every one of these has a silent
# failure mode: a license from the wrong channel installs a different release
# sequence than this repo was tested against; missing bootstrap secrets leave
# pods in CreateContainerConfigError twenty minutes in; a missing AWS LB
# controller means the lobby Service just never gets an address — no error,
# no event worth reading, nothing.
#
# The install itself waits up to 15m for the admin console, then a 30m watch
# loop polls app readiness. The loop prints not-ready deployments and the
# lobby Service's recent events on every pass because NLB provisioning is the
# canonical way this install fails (EIP/subnet mismatch, controller webhook
# down) and the only diagnostic is a k8s Event on that Service. Re-running
# this script against an existing install is safe: kots redeploys the current
# config values.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

require kubectl aws jq terraform
need_kubeconfig

CONFIG_VALUES="${REPO_ROOT}/kots/generated/config-values.yaml"

# --- Preconditions -----------------------------------------------------------

kubectl kots version >/dev/null 2>&1 \
  || die "kubectl-kots plugin not working — install it: curl https://kots.io/install | bash"

CLUSTER="$(tf_out platform eks_cluster_name)" \
  || die "cannot read eks_cluster_name from platform — run: make platform-apply"

# Cluster identity: compare the current context's server URL against what AWS
# says this cluster's endpoint is. EKS endpoint URLs embed a per-cluster random
# ID, so equality proves the context targets exactly this cluster — including
# catching the recreated-cluster case, where a stale kubeconfig has the right
# name but a dead endpoint. Limits: needs live AWS credentials, and a context
# that legitimately reaches the cluster through a proxy or SSH tunnel fails
# the check.
EXPECTED_ENDPOINT="$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" \
  --query cluster.endpoint --output text 2>/dev/null)" \
  || die "aws eks describe-cluster ${CLUSTER} failed — are your AWS credentials current?"
CURRENT_SERVER="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || true)"
if [ -z "$CURRENT_SERVER" ]; then
  die "no current kubectl context — run: make kubeconfig"
fi
if [ "$CURRENT_SERVER" != "$EXPECTED_ENDPOINT" ]; then
  die "kubectl context points at ${CURRENT_SERVER}, not cluster ${CLUSTER} (${EXPECTED_ENDPOINT}) — run: make kubeconfig"
fi

[ -s "$LICENSE_FILE" ] \
  || die "license missing at ${LICENSE_FILE} — download it from the Replicated vendor portal and place it there"
[ -n "$REPLICATED_CHANNEL_SLUG" ] \
  || die "replicated_channel_slug is empty in install.conf — the slug of the channel your license is bound to"
# The license names its channel; the slug in install.conf must be that
# channel's, or kots refuses the upstream ("channel slug ... is not allowed by
# license") after the preflights have run.
LICENSE_CHANNEL="$(grep -m1 -E '^\s*channelName:' "$LICENSE_FILE" | awk '{print $2}')"
info "license channel: ${LICENSE_CHANNEL}; installing from slug ${REPLICATED_CHANNEL_SLUG}"

[ -s "$CONFIG_VALUES" ] || die "${CONFIG_VALUES#"${REPO_ROOT}"/} missing — run: make config-values"

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 \
  || die "namespace ${NAMESPACE} does not exist — run: make workloads-apply"

# The full set the app manifests mount. Present-but-empty is not checked here;
# the bootstrap job owns content correctness.
BOOTSTRAP_SECRETS=(auth postgresql redis redis-auth private-issuer smtp
  majordomo-provisioner-password missioncontrol-provisioner-password oidc
  scim-server-secrets postgresql-landlordcachesrv)
MISSING=()
for s in "${BOOTSTRAP_SECRETS[@]}"; do
  kubectl -n "$NAMESPACE" get secret "$s" >/dev/null 2>&1 || MISSING+=("$s")
done
if [ "${#MISSING[@]}" -ne 0 ]; then
  die "missing secrets in ${NAMESPACE}: ${MISSING[*]} — run: make workloads-apply"
fi

LB_AVAILABLE="$(kubectl -n kube-system get deploy aws-load-balancer-controller \
  -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)"
[ "$LB_AVAILABLE" = "True" ] \
  || die "aws-load-balancer-controller is not Available in kube-system — run: make workloads-apply (the lobby NLB cannot provision without it)"

# --- Admin password from Secrets Manager -------------------------------------
# Never generated here, never printed: the same password must survive
# re-installs and be retrievable by an operator who never ran this script
# (${NAME}/app/kots-admin-password in Secrets Manager).

KOTS_PW_ARN="$(tf_out_json platform app_secret_arns | jq -r '.kots_admin_password // empty')"
[ -n "$KOTS_PW_ARN" ] \
  || die "app_secret_arns has no kots_admin_password entry — run: make platform-apply"
KOTS_PW="$(aws secretsmanager get-secret-value --secret-id "$KOTS_PW_ARN" \
  --region "$REGION" --query SecretString --output text)" \
  || die "could not read KOTS admin password from Secrets Manager (${KOTS_PW_ARN})"

# --- Install -----------------------------------------------------------------

info "Preconditions passed. Installing app 'smallstep' from smallstep/${REPLICATED_CHANNEL_SLUG} into ${NAMESPACE}..."
info "(admin console password is in Secrets Manager: ${NAME}/app/kots-admin-password)"

# The upstream URI must carry the channel slug: a bare 'smallstep' makes kots
# fall back to the 'stable' slug, which a channel-restricted license refuses
# ("channel slug stable is not allowed by license"). The bare slug is correct
# only for licenses on the default channel.
kubectl kots install "smallstep/${REPLICATED_CHANNEL_SLUG}" \
  --namespace "$NAMESPACE" \
  --license-file "$LICENSE_FILE" \
  --config-values "$CONFIG_VALUES" \
  --shared-password "$KOTS_PW" \
  --no-port-forward \
  --wait-duration 15m

# --- Watch until ready -------------------------------------------------------
# `kubectl kots get apps -o json` emits a top-level array of apps with
# slug/state/versionlabel fields; select the row by slug and read .state —
# no positional column parsing, and other apps in the namespace cannot
# confuse the match.

BUDGET_SECS=1800
INTERVAL_SECS=30
DEADLINE=$(( $(date +%s) + BUDGET_SECS ))

info "Waiting up to $(( BUDGET_SECS / 60 ))m for the app to report ready..."

while :; do
  STATUS="$(kubectl kots get apps -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -r '.[] | select(.slug == "smallstep") | .state' || true)"
  if [ "$STATUS" = "ready" ]; then
    break
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    die "app not ready after $(( BUDGET_SECS / 60 ))m (status: ${STATUS:-unknown}) — inspect with: make kots-console"
  fi

  info "app status: ${STATUS:-unknown}"
  echo "  not-ready deployments:"
  kubectl -n "$NAMESPACE" get deploy -o json 2>/dev/null \
    | jq -r '.items[]
        | select((.status.readyReplicas // 0) < (.spec.replicas // 1))
        | "    \(.metadata.name)  \(.status.readyReplicas // 0)/\(.spec.replicas // 1)"' \
    || true
  echo "  lobby Service events (NLB provisioning failures surface here):"
  kubectl -n "$NAMESPACE" describe svc lobby 2>/dev/null | tail -n 10 | sed 's/^/    /' || true
  echo ""
  sleep "$INTERVAL_SECS"
done

info "App is ready."
echo ""
echo "Next: make dns-reconcile   # point control.infra.${BASE_DOMAIN} at the mission-control NLB"
