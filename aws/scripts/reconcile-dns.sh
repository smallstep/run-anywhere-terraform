#!/bin/bash
# Point control.infra.<domain> at the mission-control NLB, then assert the
# whole DNS story. mission-control is the one Service the KOTS app creates
# with its own NLB and no pre-allocated EIP: the lobby's addresses are known
# to Terraform before the install (EIP allocations), so platform writes
# those records, but the mission-control NLB hostname exists only after the
# AWS LB controller provisions it. Something has to copy that hostname into
# Route53 after the fact.
#
# That something is this script rather than external-dns: a 25-line reconciler
# for exactly one record beats operating a controller with cluster-wide
# Route53 write access, IRSA policy, ownership TXT records, and its own
# failure modes. The trade is deliberate — the cost is that this script must
# be re-run if the NLB is ever recreated (`make dns-reconcile`, idempotent
# UPSERT).
#
# The assertions afterwards pin the failure modes that produce a
# working-looking install with broken clients: app/<wildcard>.ca must resolve
# to exactly the lobby EIP set (a partial set means an EIP/subnet mismatch);
# crl.<domain> must NOT resolve to a lobby EIP — the record aliases the S3
# CRL bucket, and because the KOTS app derives the bucket name from the
# domain, a wildcard swallowing crl.* sends CRL fetches to the lobby, which
# answers 404 and breaks revocation checking only for clients that enforce it.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

require kubectl aws jq dig terraform

ZONE_ID="$(tf_out platform route53_zone_id)" \
  || die "cannot read route53_zone_id from platform — run: make platform-apply"

RECORD="control.infra.${BASE_DOMAIN}"

# --- Wait for the mission-control NLB hostname -------------------------------
# The LB controller typically needs 2-3 minutes after the Service appears;
# 10m covers controller restarts.

BUDGET_SECS=600
INTERVAL_SECS=15
DEADLINE=$(( $(date +%s) + BUDGET_SECS ))

info "Waiting for the mission-control Service to get an NLB hostname..."
NLB_HOSTNAME=""
while :; do
  NLB_HOSTNAME="$(kubectl -n "$NAMESPACE" get svc mission-control \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -n "$NLB_HOSTNAME" ]; then
    break
  fi
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    die "mission-control has no LoadBalancer hostname after $(( BUDGET_SECS / 60 ))m — check: kubectl -n ${NAMESPACE} describe svc mission-control"
  fi
  info "  not yet — retrying in ${INTERVAL_SECS}s"
  sleep "$INTERVAL_SECS"
done

info "mission-control NLB: ${NLB_HOSTNAME}"

# --- UPSERT the CNAME --------------------------------------------------------
# TTL 300: low enough that an NLB recreation plus re-run converges within
# minutes, high enough not to hammer the resolver.

BATCH="$(jq -n --arg name "${RECORD}." --arg value "$NLB_HOSTNAME" '{
  Comment: "mission-control NLB (scripts/reconcile-dns.sh)",
  Changes: [{
    Action: "UPSERT",
    ResourceRecordSet: {
      Name: $name,
      Type: "CNAME",
      TTL: 300,
      ResourceRecords: [{ Value: $value }]
    }
  }]
}')"

CHANGE_ID="$(aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "$BATCH" \
  --query 'ChangeInfo.Id' --output text)" \
  || die "route53 change-resource-record-sets failed for ${RECORD}"

info "UPSERT submitted (${CHANGE_ID}); waiting for INSYNC..."
aws route53 wait resource-record-sets-changed --id "$CHANGE_ID"
info "${RECORD} -> ${NLB_HOSTNAME} is INSYNC."

# --- Assertions --------------------------------------------------------------

EXPECTED_EIPS="$(tf_out_json platform lobby_eip_public_ips | jq -r '.[]' | sort)"
[ -n "$EXPECTED_EIPS" ] || die "lobby_eip_public_ips output is empty — run: make platform-apply"

# resolve NAME — A records only, sorted. dig +short interleaves CNAME targets
# with addresses, hence the IPv4 filter. `|| true` because grep's no-match
# exit code is not an error here.
resolve() {
  dig +short "$1" A | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort || true
}

# assert_eips NAME — NAME must resolve to exactly the lobby EIP set. Retries
# briefly: Route53 is INSYNC above, but the operator's resolver may hold a
# cached NXDOMAIN from before the zone was delegated.
assert_eips() {
  local name="$1" got tries=0
  while :; do
    got="$(resolve "$name")"
    if [ "$got" = "$EXPECTED_EIPS" ]; then
      info "ok: ${name} -> lobby EIPs"
      return 0
    fi
    tries=$(( tries + 1 ))
    if [ "$tries" -ge 8 ]; then
      die "${name} resolves to [$(echo "$got" | tr '\n' ' ')] not the lobby EIP set [$(echo "$EXPECTED_EIPS" | tr '\n' ' ')] — check zone delegation and platform records"
    fi
    info "  ${name} not settled yet — retrying (${tries}/8)"
    sleep 15
  done
}

info "Asserting the DNS story against the lobby EIP set..."
assert_eips "app.${BASE_DOMAIN}"
# Any label proves the *.ca wildcard; "x" is not a real authority.
assert_eips "x.ca.${BASE_DOMAIN}"

CRL_IPS="$(resolve "crl.${BASE_DOMAIN}")"
if [ -z "$CRL_IPS" ]; then
  warn "crl.${BASE_DOMAIN} does not resolve yet — acceptable if the record is still propagating, but verify before the test matrix"
else
  OVERLAP="$(comm -12 <(printf '%s\n' "$EXPECTED_EIPS") <(printf '%s\n' "$CRL_IPS"))"
  if [ -n "$OVERLAP" ]; then
    die "crl.${BASE_DOMAIN} resolves to lobby EIP(s) [$(echo "$OVERLAP" | tr '\n' ' ')] — it must alias the S3/CloudFront CRL endpoint, not the lobby (a wildcard is swallowing it)"
  fi
  info "ok: crl.${BASE_DOMAIN} does not point at the lobby"
fi

info "DNS reconciled."
echo ""
echo "Next: make provision   # first-boot team, authority, SSH CA, IdP"
