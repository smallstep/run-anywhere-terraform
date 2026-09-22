#!/bin/bash
# Render kots/config-values.tmpl.yaml -> kots/generated/config-values.yaml
# from platform outputs. This is the seam between Terraform and
# KOTS: Terraform knows the ARNs, hostnames, and EIP allocations; KOTS wants
# one flat YAML of strings. A script owns the seam because neither tool does —
# templatefile() in Terraform would drag the KOTS install into Terraform's
# dependency graph (rejected in the Makefile header), and KOTS has no way to
# read remote state.
#
# The outputs are read with `terraform output -json` exactly ONCE into
# build/platform-outputs.json and every value is jq'd from that file. One read
# means one consistent snapshot: `terraform output` hits the state backend per
# invocation, so per-value reads are slow (SSO round-trips) and can straddle
# an apply, yielding a config that mixes old and new infrastructure.
#
# Failure modes this guards against: a leftover
# %TOKEN% in the rendered file is accepted by KOTS and becomes a literal
# config value (the grep at the end dies instead); an EIP count that does not
# match the public subnet count makes the AWS LB controller reject the lobby
# Service with only a k8s Event to show for it (counted here, minutes earlier);
# an empty output — root not applied, or applied with -target — renders an
# empty string that boots a half-configured platform (every substitution
# refuses empty/null).
#
# Env knobs (all optional): CERT_ISSUER (default letsencrypt; set "private"
# or "selfsigned" to exercise the trust-bundle path), EMAIL_FROM (default
# no-reply@<base_domain>), EMAIL_FROM_NAME (default Smallstep). The technical
# contact address comes from install.conf (technical_contact_email).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

require terraform jq

TPL="${REPO_ROOT}/kots/config-values.tmpl.yaml"
OUT_DIR="${REPO_ROOT}/kots/generated"
OUT="${OUT_DIR}/config-values.yaml"
TF_JSON="${BUILD_DIR}/platform-outputs.json"

[ -f "$TPL" ] || die "template not found: ${TPL}"

info "Reading terraform outputs from platform (once)..."
terraform -chdir="${REPO_ROOT}/platform" output -json > "$TF_JSON" \
  || die "could not read platform outputs — run: make platform-init"

jq -e 'has("region")' "$TF_JSON" >/dev/null \
  || die "platform has no outputs — run: make platform-apply"

# out NAME [FILTER] — one value from the snapshot. Default filter is .value;
# lists pass e.g. '.value | join(",")'.
out() {
  jq -r ".$1 | ${2:-.value}" "$TF_JSON"
}

TF_REGION="$(out region)"
TF_BASE_DOMAIN="$(out base_domain)"
APP_IAM_ROLE_ARN="$(out app_iam_role_arn)"
GATEWAY_JWT_SIGNING_KEY="$(out gateway_jwt_signing_key)"
GATEWAY_JWT_SIGNING_PUBKEY_B64="$(out gateway_jwt_signing_pubkey_b64)"
RDS_HOST="$(out rds_host)"
RDS_PORT="$(out rds_port)"
REDIS_HOST="$(out redis_host)"
REDIS_PORT="$(out redis_port)"
SMTP_HOST="$(out smtp_host)"
SMTP_PORT="$(out smtp_port)"
SMTP_USERNAME="$(out smtp_username)"
LOBBY_EIP_ALLOCATION_IDS="$(out lobby_eip_allocation_ids '.value | join(",")')"

CERT_ISSUER="${CERT_ISSUER:-letsencrypt}"
TECH_CONTACT="$(conf technical_contact_email)"
[ -n "$TECH_CONTACT" ] || die "technical_contact_email is empty in install.conf (Let's Encrypt registers it and the platform shows it to users)"
EMAIL_FROM="${EMAIL_FROM:-no-reply@${BASE_DOMAIN}}"
EMAIL_FROM_NAME="${EMAIL_FROM_NAME:-Smallstep}"

# update_trust_bundle follows CERT_ISSUER: "1" makes landlord mount the
# smallstep-trust-store ConfigMap, which the app only creates for private/
# selfsigned issuers — under letsencrypt that mount does not exist and
# landlord sticks in ContainerCreating. The letsencrypt branch must emit an
# explicit "0" (matching the Config default), not omit the value: subst
# refuses empty values, and a missing token would fail the leftover check.
case "$CERT_ISSUER" in
  private | selfsigned) UPDATE_TRUST_BUNDLE=1 ;;
  *) UPDATE_TRUST_BUNDLE=0 ;;
esac

# The state must describe THIS deployment. Stale credentials or a copied
# backend.hcl pointing at another deployment's bucket render a perfectly
# plausible config for the wrong infrastructure; the only tell is these values.
[ "$TF_BASE_DOMAIN" = "$BASE_DOMAIN" ] \
  || die "terraform says base_domain=${TF_BASE_DOMAIN} but install.conf says ${BASE_DOMAIN} — wrong state?"
[ "$TF_REGION" = "$REGION" ] \
  || die "terraform says region=${TF_REGION} but install.conf says ${REGION} — wrong state?"

EIP_COUNT="$(out lobby_eip_allocation_ids '.value | length')"
SUBNET_COUNT="$(out public_subnet_ids '.value | length')"
[ "$EIP_COUNT" = "$SUBNET_COUNT" ] \
  || die "lobby EIP count (${EIP_COUNT}) != public subnet count (${SUBNET_COUNT}) — the NLB annotation requires them equal; fix platform before installing"

SED_SCRIPT="${BUILD_DIR}/config-values.sed"
: > "$SED_SCRIPT"

# subst TOKEN VALUE — append one substitution. Values pass through a sed
# replacement string, so \, & and the | delimiter must be escaped (the base64
# pubkey contains / — hence | as delimiter). Empty and "null" are refused:
# both mean an output that does not describe real infrastructure.
subst() {
  local token="$1" value="$2" esc
  { [ -n "$value" ] && [ "$value" != "null" ]; } \
    || die "empty value for %${token}% — is platform fully applied?"
  esc="$(printf '%s' "$value" | sed -e 's/[&|\\]/\\&/g')"
  printf 's|%%%s%%|%s|g\n' "$token" "$esc" >> "$SED_SCRIPT"
}

subst TEAM_NAME "$TEAM_NAME"
subst TEAM_SLUG "$TEAM_SLUG"
subst REGION "$TF_REGION"
subst APP_IAM_ROLE_ARN "$APP_IAM_ROLE_ARN"
subst GATEWAY_JWT_SIGNING_KEY "$GATEWAY_JWT_SIGNING_KEY"
subst GATEWAY_JWT_SIGNING_PUBKEY_B64 "$GATEWAY_JWT_SIGNING_PUBKEY_B64"
subst BASE_DOMAIN "$TF_BASE_DOMAIN"
subst LOBBY_EIP_ALLOCATION_IDS "$LOBBY_EIP_ALLOCATION_IDS"
subst RDS_HOST "$RDS_HOST"
subst RDS_PORT "$RDS_PORT"
subst REDIS_HOST "$REDIS_HOST"
subst REDIS_PORT "$REDIS_PORT"
subst CERT_ISSUER "$CERT_ISSUER"
subst UPDATE_TRUST_BUNDLE "$UPDATE_TRUST_BUNDLE"
subst TECH_CONTACT "$TECH_CONTACT"
subst EMAIL_FROM "$EMAIL_FROM"
subst EMAIL_FROM_NAME "$EMAIL_FROM_NAME"
subst SMTP_HOST "$SMTP_HOST"
subst SMTP_PORT "$SMTP_PORT"
subst SMTP_USERNAME "$SMTP_USERNAME"

mkdir -p "$OUT_DIR"
sed -f "$SED_SCRIPT" "$TPL" > "$OUT"

# Any surviving %TOKEN% means the template grew a placeholder this script does
# not know — KOTS would accept it as a literal string. Comment lines are
# exempt: the template's own header documents the placeholder mechanism.
if LEFTOVER="$(awk '/^[[:space:]]*#/ { next }
    /%[A-Z0-9_]+%/ { print FNR ": " $0; found = 1 }
    END { exit !found }' "$OUT")"; then
  echo "$LEFTOVER" >&2
  die "unrendered tokens remain in ${OUT} — add them to $(basename "$0")"
fi

info "Rendered ${OUT#"${REPO_ROOT}"/}"
echo ""
echo "Non-obvious values:"
echo "  base_domain              ${TF_BASE_DOMAIN}"
echo "  aws_nlb_ip               ${LOBBY_EIP_ALLOCATION_IDS}  (${EIP_COUNT} EIPs = ${SUBNET_COUNT} public subnets)"
echo "  aws_cluster_iam_role     ${APP_IAM_ROLE_ARN}"
echo "  gateway_jwt_signing_key  ${GATEWAY_JWT_SIGNING_KEY}"
echo "  postgres                 ${RDS_HOST}:${RDS_PORT} (TLS required, user smallstep)"
echo "  redis                    ${REDIS_HOST}:${REDIS_PORT} (TLS + AUTH)"
echo "  smtp                     ${SMTP_USERNAME}@${SMTP_HOST}:${SMTP_PORT} from ${EMAIL_FROM}"
echo "  cert_issuer              ${CERT_ISSUER}"
echo "  technical_contact_email  ${TECH_CONTACT}"
echo ""
echo "Next: make kots-install"
