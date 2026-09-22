# Provider requirements only — configuration lives in the workloads root,
# which builds the kubernetes/helm client config from stage 1's EKS outputs.
#
# Deliberately no aws provider: nothing in this module calls AWS directly.
# The controllers it installs do, at run time, using the IRSA roles stage 1
# created — Terraform hands over role ARNs and never touches the APIs itself.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.38"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
  }
}
