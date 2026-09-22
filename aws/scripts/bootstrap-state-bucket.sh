#!/bin/bash
# One-time bootstrap of the Terraform state bucket — the single deliberate
# not-Terraform step, because the bucket must exist before `terraform init`.
# Idempotent: re-running converges and rewrites every root's backend.hcl.
#
#   scripts/bootstrap-state-bucket.sh
#   make platform-init
#
# Reads install.conf. Creates <name>-tfstate-<account-id> in the region with
# versioning, SSE, and a public-access block. Locking is S3-native
# (use_lockfile) — no DynamoDB table.
#
# Both roots share this one bucket under their own keys, so each stays
# independently plannable and destroyable.

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${INFRA_DIR}/.." && pwd)"

# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/lib.sh"

require aws

EXPECT_ACCOUNT="$(conf account_id)"
[ -n "$REGION" ] || die "region missing in install.conf"

AWS_ARGS=(--region "$REGION")
ACCOUNT_ID="$(aws "${AWS_ARGS[@]}" sts get-caller-identity --query Account --output text)" \
  || die "could not reach AWS — are your credentials current?"

# Guard against pointing this at the wrong account. This script creates
# buckets; being in the wrong account by accident is not a recoverable mistake.
if [ -z "$EXPECT_ACCOUNT" ]; then
  die "account_id is empty in install.conf — fill it in before bootstrapping"
fi
if [ "$ACCOUNT_ID" != "$EXPECT_ACCOUNT" ]; then
  die "wrong account: authenticated as ${ACCOUNT_ID}, install.conf expects ${EXPECT_ACCOUNT}"
fi

BUCKET="${NAME}-tfstate-${ACCOUNT_ID}"

if aws "${AWS_ARGS[@]}" s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  info "State bucket s3://${BUCKET} already exists."
else
  info "Creating state bucket s3://${BUCKET}..."
  if [ "$REGION" = "us-east-1" ]; then
    aws "${AWS_ARGS[@]}" s3api create-bucket --bucket "$BUCKET" >/dev/null
  else
    aws "${AWS_ARGS[@]}" s3api create-bucket --bucket "$BUCKET" \
      --create-bucket-configuration "LocationConstraint=${REGION}" >/dev/null
  fi
fi

aws "${AWS_ARGS[@]}" s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws "${AWS_ARGS[@]}" s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  'BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true'
aws "${AWS_ARGS[@]}" s3api put-bucket-encryption --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# One backend.hcl per root. State keys mirror the directory layout so an
# operator reading `aws s3 ls` can tell what is deployed at a glance.
write_backend() {
  local root_dir="$1" state_key="$2"
  [ -d "${REPO_ROOT}/${root_dir}" ] || return 0
  cat > "${REPO_ROOT}/${root_dir}/backend.hcl" <<EOF
# Written by scripts/bootstrap-state-bucket.sh — gitignored, regenerate freely.
bucket       = "${BUCKET}"
key          = "${state_key}"
region       = "${REGION}"
use_lockfile = true
EOF
  info "  wrote ${root_dir}/backend.hcl  (key=${state_key})"
}

write_backend "platform"  "platform.tfstate"
write_backend "workloads" "workloads.tfstate"

info "State bucket ready: s3://${BUCKET}"
echo ""
echo "Next:"
echo "  make platform-init && make platform-apply"
echo "  # then delegate NS records for the domain to the Route53 zone, then:"
echo "  make workloads-init && make workloads-apply"
