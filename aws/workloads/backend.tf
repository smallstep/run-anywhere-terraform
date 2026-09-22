# Backend config lives in backend.hcl (copy backend.hcl.example; keep it out of
# git). The bucket must exist first — see the README. Init with:
#
#   terraform -chdir=aws/workloads init -backend-config=backend.hcl

terraform {
  backend "s3" {}
}
