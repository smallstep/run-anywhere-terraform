#!/bin/bash
# Write the deployment-owned kubeconfig. Every script and make target reads the
# cluster through $KUBECONFIG (exported by lib.sh and the Makefile) rather than
# through ~/.kube/config's current context — so the only cluster this repo can
# ever address is the one platform built. Re-run freely; it is idempotent.

set -euo pipefail

# shellcheck source=scripts/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require aws kubectl terraform

CLUSTER="$(tf_out platform eks_cluster_name 2>/dev/null || true)"
[ -n "$CLUSTER" ] || die "platform has no eks_cluster_name output — run: make platform-apply"

mkdir -p "$(dirname "$KUBECONFIG")"
info "Writing ${KUBECONFIG} for cluster ${CLUSTER} (${REGION})"
aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" --kubeconfig "$KUBECONFIG" >/dev/null
chmod 0600 "$KUBECONFIG"

ACCOUNT="$(conf account_id)"
CTX="$(kubectl config current-context)"
case "$CTX" in
  *:"${ACCOUNT}":cluster/"${CLUSTER}") info "Context: ${CTX}" ;;
  *) die "kubeconfig context ${CTX} is not account ${ACCOUNT} cluster ${CLUSTER} — refusing to proceed" ;;
esac

info "Done. Scripts and make targets now use this file; your ~/.kube/config is untouched."
