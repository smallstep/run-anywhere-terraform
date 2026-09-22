#!/bin/bash
# Staged verification: crisp pass/fail checks, one stage per install phase.
#
#   scripts/verify.sh <platform|dns|cluster|app>
#
# Each stage is a bash function of independent checks; a failing check prints
# FAIL and the stage keeps going (one broken thing should not hide the next),
# then the stage exits nonzero if anything failed. Stages are ordered by the
# install path: platform proves the AWS layer matches what Terraform promised,
# dns proves the delegation is live BEFORE the KOTS install burns 20 minutes
# to a cert-manager timeout, cluster proves the addons and bootstrap job left
# the cluster in the shape the app expects, and app proves the running
# platform.
#
# Checks compare AWS reality against the SAME sources the build used: terraform
# outputs (via tf_out) for identities, and the platform tfvars pins for
# tunables (falling back to the variables.tf default when tfvars does not set
# one — exactly Terraform's own resolution order). Nothing here re-declares a
# value that exists elsewhere; drift between tfvars and reality is precisely
# what the platform stage is for.
#
# Every check is written as if/then/else, never `cond && ok || bad`: under
# `set -e` a bare failing test would abort the whole stage, and the &&/|| form
# hides that trap. The verbosity buys a stage that always runs to its verdict.
#
# Known failure modes:
#   - `aws` calls here are all read-only (describe/get/list); safe on prod
#     credentials, but they DO need a live SSO session — a silent token expiry
#     looks like every check failing at once. Run `aws sso login` first.
#   - The cluster stage's psql probe runs a one-off pod IN the cluster because
#     RDS is only reachable from the VPC. `kubectl run --rm -i` occasionally
#     leaks the pod on Ctrl-C; `kubectl -n smallstep delete pod psql-verify`
#     cleans up.
#   - The DB-name list below mirrors the bootstrap job's list (modules/
#     smallstep-bootstrap is the authority). If the app version changes its
#     schema layout, update both or the check lies.

set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require aws jq kubectl

PASS_COUNT=0
FAIL_COUNT=0

ok()   { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS  %s\n' "$*"; }
bad()  { FAIL_COUNT=$((FAIL_COUNT + 1)); printf 'FAIL  %s\n' "$*"; }
warn_check() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'WARN  %s\n' "$*"; }
skip() { printf 'SKIP  %s\n' "$*"; }
note() { printf '      %s\n' "$*"; }

# tf_var NAME DEFAULT — a platform tunable, resolved like Terraform does:
# terraform.tfvars first, then the variables.tf default, then DEFAULT.
tf_var() {
  local root="${REPO_ROOT}/platform" v
  v="$(sed -n -E "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"?([^\"[:space:]]+)\"?.*/\\1/p" \
        "${root}/terraform.tfvars" 2>/dev/null | head -1)"
  if [ -z "$v" ]; then
    v="$(awk -v name="$1" '
      $1 == "variable" && $2 == "\"" name "\"" { inblock = 1 }
      inblock && $1 == "default" { gsub(/[="[:space:]]/, "", $0); sub(/^default/, "", $0); print; exit }
      inblock && /^}/ { exit }
    ' "${root}/variables.tf" 2>/dev/null)"
  fi
  echo "${v:-${2:-}}"
}

verdict() {
  echo
  echo "-------------------------------------------------------------"
  echo "verify ${STAGE}: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
  [ "$FAIL_COUNT" -eq 0 ] || exit 1
}

# =============================================================================
# platform — the AWS layer, straight from the service APIs
# =============================================================================

stage_platform() {
  local cluster eks ver pin pub want_private logs
  cluster="$(tf_out platform eks_cluster_name)"
  eks="$(aws eks describe-cluster --name "$cluster" --region "$REGION")"

  ver="$(jq -r .cluster.version <<<"$eks")"
  pin="$(tf_var eks_version 1.31)"
  if [ "$ver" = "$pin" ]; then ok "EKS version ${ver} matches tfvars pin"
  else bad "EKS version ${ver}, tfvars pins ${pin}"; fi

  pub="$(jq -r .cluster.resourcesVpcConfig.endpointPublicAccess <<<"$eks")"
  want_private="$(tf_var cluster_endpoint_private_only false)"
  if [ "$want_private" = "true" ]; then
    if [ "$pub" = "false" ]; then ok "EKS endpoint private-only (as pinned)"
    else bad "EKS endpoint is public but tfvars pins private-only"; fi
  else
    if [ "$pub" = "true" ]; then ok "EKS endpoint public access enabled (as pinned)"
    else bad "EKS endpoint public access disabled but tfvars expects it"; fi
  fi

  logs="$(jq -r '[.cluster.logging.clusterLogging[] | select(.enabled) | .types[]] | join(" ")' <<<"$eks")"
  local t missing=""
  for t in api audit authenticator; do
    grep -qw "$t" <<<"$logs" || missing="${missing} ${t}"
  done
  if [ -z "$missing" ]; then ok "EKS control-plane logging includes api/audit/authenticator"
  else bad "EKS control-plane logging missing:${missing} (enabled: ${logs:-none})"; fi

  # --- RDS: located by endpoint, because the identifier is module-internal
  local rds_host inst engine engver enc maz pgrp force_ssl
  rds_host="$(tf_out platform rds_host)"
  inst="$(aws rds describe-db-instances --region "$REGION" \
          --query "DBInstances[?Endpoint.Address=='${rds_host}'] | [0]" --output json)"
  if [ "$inst" = "null" ] || [ -z "$inst" ]; then
    bad "no RDS instance found with endpoint ${rds_host}"
  else
    engine="$(jq -r .Engine <<<"$inst")"
    if [ "$engine" = "postgres" ]; then ok "RDS engine is postgres"
    else bad "RDS engine is ${engine}, expected postgres"; fi

    engver="$(jq -r .EngineVersion <<<"$inst")"
    if [ "${engver%%.*}" -ge 14 ]; then ok "RDS engine version ${engver} >= 14"
    else bad "RDS engine version ${engver} < 14 (platform minimum)"; fi

    enc="$(jq -r .StorageEncrypted <<<"$inst")"
    if [ "$enc" = "true" ]; then ok "RDS storage encrypted"
    else bad "RDS storage NOT encrypted"; fi

    maz="$(jq -r .MultiAZ <<<"$inst")"
    ok "RDS MultiAZ=${maz} (tfvars pins $(tf_var db_multi_az false))"

    # rds.force_ssl lives in the IN-USE parameter group, not the default one —
    # checking the wrong group is how this passes while connections stay plain.
    # describe-db-parameters paginates and the CLI applies --query per page,
    # yielding one line per page ("None" where the param isn't on that page).
    # Filter to the real value client-side.
    pgrp="$(jq -r '.DBParameterGroups[0].DBParameterGroupName' <<<"$inst")"
    force_ssl="$(aws rds describe-db-parameters --region "$REGION" \
                 --db-parameter-group-name "$pgrp" \
                 --query "Parameters[?ParameterName=='rds.force_ssl'].ParameterValue" \
                 --output text | grep -vx 'None' | head -1)"
    if [ "$force_ssl" = "1" ]; then ok "rds.force_ssl=1 in parameter group ${pgrp}"
    else bad "rds.force_ssl='${force_ssl}' in ${pgrp}, expected 1"; fi
  fi

  # --- ElastiCache: located by endpoint address, same reasoning as RDS
  local redis_host rg f
  redis_host="$(tf_out platform redis_host)"
  rg="$(aws elasticache describe-replication-groups --region "$REGION" --output json \
        | jq --arg h "$redis_host" '[.ReplicationGroups[]
            | select((.ConfigurationEndpoint.Address // "") == $h
                     or ([.NodeGroups[]?.PrimaryEndpoint.Address] | index($h) != null))] | first')"
  if [ "$rg" = "null" ] || [ -z "$rg" ]; then
    bad "no ElastiCache replication group found with endpoint ${redis_host}"
  else
    for f in TransitEncryptionEnabled AtRestEncryptionEnabled AuthTokenEnabled; do
      if [ "$(jq -r ".${f}" <<<"$rg")" = "true" ]; then ok "ElastiCache ${f}"
      else bad "ElastiCache ${f} is not true"; fi
    done
  fi

  # --- Lobby EIPs: the NLB annotation needs exactly one per public subnet
  local eip_count
  eip_count="$(tf_out_json platform lobby_eip_public_ips | jq length)"
  if [ "$eip_count" -eq 3 ]; then ok "3 lobby EIPs allocated"
  else bad "${eip_count} lobby EIPs, expected 3"; fi

  # --- CRL bucket: existence plus a policy that matches the declared mode
  local bucket mode policy
  bucket="$(tf_out platform crl_bucket_name)"
  if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
    ok "CRL bucket ${bucket} exists"
    mode="$(tf_var crl_mode public-bucket)"
    policy="$(aws s3api get-bucket-policy --bucket "$bucket" --query Policy --output text 2>/dev/null || true)"
    if [ -z "$policy" ]; then
      bad "CRL bucket has no bucket policy (mode ${mode} requires one)"
    elif [ "$mode" = "public-bucket" ]; then
      if jq -e '.Statement[] | select(.Effect == "Allow")
                | select((.Principal == "*") or (.Principal.AWS? == "*"))
                | select([.Action] | flatten | index("s3:GetObject"))' <<<"$policy" >/dev/null; then
        ok "CRL bucket policy allows anonymous s3:GetObject (public-bucket mode)"
      else
        bad "CRL bucket policy lacks the anonymous GetObject grant public-bucket mode needs"
      fi
    else
      if grep -q 'cloudfront' <<<"$policy" && grep -q 'SourceArn' <<<"$policy"; then
        ok "CRL bucket policy is CloudFront-scoped via SourceArn (cloudfront mode)"
      else
        bad "CRL bucket policy is not CloudFront/SourceArn-scoped but crl_mode=cloudfront"
      fi
    fi
  else
    bad "CRL bucket ${bucket} does not exist (or not visible to this profile)"
  fi

  # --- Gateway JWT key: the KOTS config hands the app this exact key id and
  # the app assumes P-256; a wrong KeySpec surfaces much later as opaque JWT
  # verification failures, so pin it here.
  local key_uri key_id key_spec
  key_uri="$(tf_out platform gateway_jwt_signing_key)"
  key_id="${key_uri#awskms:key-id=}"
  key_spec="$(aws kms get-public-key --region "$REGION" --key-id "$key_id" \
              --query KeySpec --output text 2>/dev/null || true)"
  if [ "$key_spec" = "ECC_NIST_P256" ]; then ok "gateway JWT key is P-256 (${key_id})"
  else bad "gateway JWT key KeySpec='${key_spec}', expected ECC_NIST_P256"; fi

  # --- Every app secret ARN must resolve, or the bootstrap job dies at 2am
  local name arn
  while read -r name arn; do
    if aws secretsmanager describe-secret --region "$REGION" --secret-id "$arn" >/dev/null 2>&1; then
      ok "secret ${name} resolves"
    else
      bad "secret ${name} (${arn}) does not resolve"
    fi
  done < <(tf_out_json platform app_secret_arns | jq -r 'to_entries[] | "\(.key) \(.value)"')
}

# =============================================================================
# dns — delegation live, app names on the lobby EIPs, CRL name elsewhere
# =============================================================================

stage_dns() {
  require dig

  # Resolver pinned to 1.1.1.1: the question is what the PUBLIC internet sees
  # (Let's Encrypt validates from outside), not what a lucky local cache says.
  local ns
  ns="$(dig +short NS "$BASE_DOMAIN" @1.1.1.1)"
  if [ -n "$ns" ]; then
    ok "NS delegation for ${BASE_DOMAIN} is live"
  else
    bad "no NS records for ${BASE_DOMAIN} at 1.1.1.1 — delegation not done"
    note "The parent zone must delegate to this deployment's Route53 zone before"
    note "anything else can work (Let's Encrypt included)."
    verdict
  fi

  local eips answers host
  eips="$(tf_out_json platform lobby_eip_public_ips | jq -r '.[]' | sort)"
  for host in "app.${BASE_DOMAIN}" "probe.ca.${BASE_DOMAIN}"; do
    answers="$(dig +short A "$host" @1.1.1.1 | grep -E '^[0-9.]+$' | sort || true)"
    if [ "$answers" = "$eips" ]; then
      ok "${host} resolves to exactly the lobby EIP set"
    else
      bad "${host} A records differ from the lobby EIPs"
      note "got:  $(tr '\n' ' ' <<<"$answers")"
      note "want: $(tr '\n' ' ' <<<"$eips")"
    fi
  done

  # crl.<domain> serves from S3/CloudFront, never the lobby: sharing an IP with
  # the app would put plain-HTTP CRL fetches through the TLS-only NLB.
  local crl_ips overlap
  crl_ips="$(dig +short A "crl.${BASE_DOMAIN}" @1.1.1.1 | grep -E '^[0-9.]+$' | sort || true)"
  if [ -z "$crl_ips" ]; then
    bad "crl.${BASE_DOMAIN} does not resolve"
  else
    overlap="$(comm -12 <(echo "$eips") <(echo "$crl_ips"))"
    if [ -z "$overlap" ]; then ok "crl.${BASE_DOMAIN} resolves outside the lobby EIP set"
    else bad "crl.${BASE_DOMAIN} resolves to a lobby EIP (${overlap}) — it must not"; fi
  fi
}

# =============================================================================
# cluster — addons, bootstrap job, secrets, and the database contract
# =============================================================================

# The bootstrap job pre-creates these six databases; the app creates the rest
# itself at boot (that is why role smallstep needs CREATEDB — checked below).
# This list mirrors modules/smallstep-bootstrap, which is the authority.
# Override for a divergent app version: DB_LIST="a b c" scripts/verify.sh cluster
# Must agree with modules/smallstep-bootstrap/templates/bootstrap.sh.tftpl:
# the five DBs the install docs require pre-created, plus landlord (pre-created
# so the landlordcachesrv replication grant has a target before first boot).
DB_LIST="${DB_LIST:-bouncer gateway guardian inventory mission_control landlord}"

stage_cluster() {
  need_kubeconfig
  local ready
  ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 == "Ready"' | wc -l)"
  if [ "$ready" -ge 3 ]; then ok "${ready} nodes Ready (>= 3)"
  else bad "only ${ready} nodes Ready, need >= 3"; fi

  if kubectl -n kube-system get deploy aws-load-balancer-controller -o json 2>/dev/null \
    | jq -e '.status.conditions[]? | select(.type == "Available" and .status == "True")' >/dev/null; then
    ok "aws-load-balancer-controller Available"
  else
    bad "aws-load-balancer-controller not Available"
  fi

  # Exactly one default StorageClass and it must be gp3: the app's PVCs bind to
  # the default, and gp2 left as a second default makes binding nondeterministic.
  local defaults
  defaults="$(kubectl get storageclass -o json \
    | jq -r '.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"] == "true") | .metadata.name')"
  if [ "$defaults" = "gp3" ]; then
    ok "default StorageClass is gp3 (and only gp3)"
  else
    bad "default StorageClass set is '$(tr '\n' ' ' <<<"$defaults")', expected exactly gp3"
  fi

  if kubectl -n "$NAMESPACE" get job smallstep-bootstrap -o json 2>/dev/null \
    | jq -e '.status.conditions[]? | select(.type == "Complete" and .status == "True")' >/dev/null; then
    ok "job smallstep-bootstrap Complete"
  else
    bad "job smallstep-bootstrap not Complete (kubectl -n ${NAMESPACE} logs job/smallstep-bootstrap)"
  fi

  local s
  for s in auth postgresql redis redis-auth private-issuer smtp \
           majordomo-provisioner-password missioncontrol-provisioner-password \
           oidc scim-server-secrets postgresql-landlordcachesrv; do
    if kubectl -n "$NAMESPACE" get secret "$s" >/dev/null 2>&1; then ok "secret ${s} exists"
    else bad "secret ${s} missing"; fi
  done

  # The app namespace must NOT be annotated for linkerd sidecar injection: the
  # app is deployed without a service mesh.
  local inject
  inject="$(kubectl get ns "$NAMESPACE" -o json | jq -r '.metadata.annotations["linkerd.io/inject"] // empty')"
  if [ -z "$inject" ]; then ok "namespace ${NAMESPACE} has no linkerd.io/inject annotation"
  else bad "namespace ${NAMESPACE} annotated linkerd.io/inject=${inject}"; fi

  # --- Database contract, checked from INSIDE the VPC (RDS is not public).
  # Credentials come from the master secret in Secrets Manager, not from any
  # in-cluster secret, so this also proves the ARN the bootstrap job used
  # still dereferences to a working login.
  local master_arn secret_json pguser pgpassword rds_host rds_port sql out in_list db
  master_arn="$(tf_out_json platform app_secret_arns | jq -r .master)"
  secret_json="$(aws secretsmanager get-secret-value --region "$REGION" \
                 --secret-id "$master_arn" --query SecretString --output text)"
  if jq -e . >/dev/null 2>&1 <<<"$secret_json"; then
    pguser="$(jq -r '.username // "postgres"' <<<"$secret_json")"
    pgpassword="$(jq -r '.password // empty' <<<"$secret_json")"
  else
    # Bare-string secret: treat it as the password for the default master user.
    pguser="postgres"
    pgpassword="$secret_json"
  fi
  rds_host="$(tf_out platform rds_host)"
  rds_port="$(tf_out platform rds_port)"

  # shellcheck disable=SC2086 # DB_LIST is a space-separated list by design
  in_list="$(printf "'%s'," $DB_LIST)"
  in_list="${in_list%,}"
  sql="
    SELECT 'db:' || datname FROM pg_database WHERE datname IN (${in_list});
    SELECT 'createdb:' || rolcreatedb FROM pg_roles WHERE rolname = 'smallstep';
    SELECT 'lcs_role:' || count(*) FROM pg_roles WHERE rolname = 'landlordcachesrv';
    SELECT 'lcs_repl:' || coalesce((SELECT true FROM pg_auth_members m
      JOIN pg_roles g ON m.roleid = g.oid JOIN pg_roles u ON m.member = u.oid
      WHERE g.rolname = 'rds_replication' AND u.rolname = 'landlordcachesrv'), false);
    SELECT 'ssl:' || setting FROM pg_settings WHERE name = 'ssl';
  "
  # PGSSLMODE=require both exercises rds.force_ssl and refuses to send the
  # master password plaintext. The pod is one-shot; psql reads SQL on stdin.
  if ! out="$(kubectl -n "$NAMESPACE" run psql-verify --rm -i --restart=Never --quiet \
          --image=postgres:16-alpine \
          --env="PGHOST=${rds_host}" --env="PGPORT=${rds_port}" \
          --env="PGUSER=${pguser}" --env="PGPASSWORD=${pgpassword}" \
          --env="PGDATABASE=postgres" --env="PGSSLMODE=require" \
          --command -- psql -tA -f - <<<"$sql" 2>&1)"; then
    bad "psql probe pod failed"
    note "$out"
    verdict
  fi

  for db in $DB_LIST; do
    if grep -q "^db:${db}$" <<<"$out"; then ok "database ${db} exists"
    else bad "database ${db} missing"; fi
  done
  # 'text || boolean' goes through the ::text cast, which renders 'true', not
  # boolout's 't'; keep the grep unanchored on the suffix.
  if grep -q '^createdb:t' <<<"$out"; then ok "role smallstep has CREATEDB"
  else bad "role smallstep lacks CREATEDB (the app cannot create its own databases)"; fi
  if grep -q '^lcs_role:1$' <<<"$out"; then ok "role landlordcachesrv exists"
  else bad "role landlordcachesrv missing"; fi
  if grep -q '^lcs_repl:t' <<<"$out"; then ok "landlordcachesrv is a member of rds_replication"
  else bad "landlordcachesrv not in rds_replication (logical replication will fail)"; fi
  if grep -q '^ssl:on$' <<<"$out"; then ok "SHOW ssl = on"
  else bad "SHOW ssl != on"; fi
}

# =============================================================================
# app — the running platform, outside-in
# =============================================================================

stage_app() {
  need_kubeconfig
  require curl step openssl dig

  local kots_out
  kots_out="$(kubectl kots get apps -n "$NAMESPACE" 2>/dev/null || true)"
  if grep -qi 'ready' <<<"$kots_out"; then ok "kots reports the app ready"
  else bad "kots does not report the app ready"; note "$kots_out"; fi

  local not_running
  not_running="$(kubectl -n "$NAMESPACE" get pods --no-headers 2>/dev/null \
                 | awk '$3 != "Running" && $3 != "Completed" && $3 != "Succeeded"' || true)"
  if [ -z "$not_running" ]; then
    ok "all pods in ${NAMESPACE} Running/Completed"
  else
    bad "non-Running pods in ${NAMESPACE}:"
    note "$not_running"
  fi

  local lb
  lb="$(kubectl -n "$NAMESPACE" get svc lobby \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -n "$lb" ]; then ok "svc lobby has an ingress hostname (${lb})"
  else bad "svc lobby has no LoadBalancer ingress hostname"; fi

  # All 3 EIPs associated proves the aws_nlb_ip KOTS config was honored — an
  # NLB that allocated its own IPs would leave these EIPs unassociated and DNS
  # (which points at the EIPs) silently broken.
  local alloc_ids assoc
  alloc_ids="$(tf_out_json platform lobby_eip_allocation_ids | jq -r '.[]' | tr '\n' ' ')"
  # shellcheck disable=SC2086 # word-splitting the id list is the point
  assoc="$(aws ec2 describe-addresses --region "$REGION" --allocation-ids $alloc_ids \
           --query 'Addresses[].AssociationId' --output json | jq '[.[] | select(. != null)] | length')"
  if [ "$assoc" -eq 3 ]; then ok "all 3 lobby EIPs associated (aws_nlb_ip honored)"
  else bad "only ${assoc}/3 lobby EIPs associated — the NLB is not on the EIPs DNS points at"; fi

  local code
  # /app, not /. The dashboard is served at /app; the bare host returns 404 by
  # design.
  code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 20 "https://app.${BASE_DOMAIN}/app" 2>/dev/null || true)"
  if [ "$code" = "200" ]; then ok "https://app.${BASE_DOMAIN}/app returns 200"
  else bad "https://app.${BASE_DOMAIN}/app returned '${code:-connection failure}'"; fi

  if step certificate inspect "https://app.${BASE_DOMAIN}" --servername "app.${BASE_DOMAIN}" 2>/dev/null \
    | grep -qi "Let's Encrypt"; then
    ok "app.${BASE_DOMAIN} serves a Let's Encrypt chain"
  else
    bad "app.${BASE_DOMAIN} certificate issuer is not Let's Encrypt (cert-manager not done?)"
  fi

  # Handshake only, no HTTP: the tunnel endpoint speaks its own protocol.
  if echo | timeout 15 openssl s_client -connect "tunnel.${BASE_DOMAIN}:443" \
    -servername "tunnel.${BASE_DOMAIN}" >/dev/null 2>&1; then
    ok "tunnel.${BASE_DOMAIN}:443 completes a TLS handshake"
  else
    bad "tunnel.${BASE_DOMAIN}:443 TLS handshake failed"
  fi

  # Warn-not-fail: control.infra points at the mission-control NLB, which only
  # exists once the app has created it and dns-reconcile has run.
  local ctrl
  ctrl="$(dig +short "control.infra.${BASE_DOMAIN}" @1.1.1.1 | head -1 || true)"
  if [ -n "$ctrl" ]; then
    ok "control.infra.${BASE_DOMAIN} resolves (${ctrl})"
  else
    warn_check "control.infra.${BASE_DOMAIN} does not resolve — run make dns-reconcile once the mission-control LB exists"
  fi

  # 403/404 are fine before the first authority publishes: the bucket exists
  # but is empty, and S3 answers empty prefixes with an error status. What we
  # are proving is only that plain-HTTP reaches the CRL origin at all.
  code="$(curl -sSI -o /dev/null -w '%{http_code}' --max-time 15 "http://crl.${BASE_DOMAIN}/" 2>/dev/null || true)"
  case "$code" in
    200 | 403 | 404) ok "http://crl.${BASE_DOMAIN}/ answers HTTP ${code}" ;;
    *) bad "http://crl.${BASE_DOMAIN}/ returned '${code:-connection failure}'" ;;
  esac

  if [ -n "${SMALLSTEP_API_TOKEN:-}" ]; then
    local api_code
    api_code="$(curl -sS -o "${BUILD_DIR}/authorities.json" -w '%{http_code}' --max-time 20 \
      -H "Authorization: Bearer ${SMALLSTEP_API_TOKEN}" \
      -H "X-Smallstep-API-Version: 2025-01-01" \
      "https://gateway.${BASE_DOMAIN}/api/authorities" 2>/dev/null || true)"
    if [ "$api_code" = "200" ] && jq -e . "${BUILD_DIR}/authorities.json" >/dev/null 2>&1; then
      ok "gateway API lists authorities (200, JSON)"
    else
      bad "gateway API /api/authorities returned '${api_code}' (body: ${BUILD_DIR}/authorities.json)"
    fi
  else
    skip "gateway API check — SMALLSTEP_API_TOKEN not set (see env.example)"
  fi

  local log_group streams
  log_group="$(tf_out platform container_log_group_name)"
  if [ -n "$log_group" ]; then
    # No --max-items: it appends a pagination "None" line to text output,
    # which breaks the integer test below.
    streams="$(aws logs describe-log-streams --region "$REGION" \
               --log-group-name "$log_group" \
               --query 'logStreams | length(@)' --output text 2>/dev/null | head -1 || echo 0)"
    if [ "$streams" -ge 1 ] 2>/dev/null; then ok "CloudWatch log group ${log_group} has streams"
    else bad "CloudWatch log group ${log_group} has no streams (fluent-bit not shipping?)"; fi
  else
    skip "CloudWatch check — enable_logging=false"
  fi
}

# =============================================================================

STAGE="${1:-}"
case "$STAGE" in
  platform) stage_platform ;;
  dns) stage_dns ;;
  cluster) stage_cluster ;;
  app) stage_app ;;
  *)
    echo "usage: $(basename "$0") <platform|dns|cluster|app>" >&2
    exit 2
    ;;
esac

verdict
