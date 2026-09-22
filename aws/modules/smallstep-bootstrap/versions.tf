# Provider requirements only — configuration lives in the workloads root.
#
# No aws provider, and that absence is load-bearing: reading the app secrets
# with a Terraform data source would copy every one of them into this stage's
# state file in plaintext. Instead the bootstrap Job fetches them at run time
# under its own IRSA identity — Terraform names the secrets, the pod reads
# them.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.38"
    }
  }
}
