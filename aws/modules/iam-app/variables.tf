variable "name" {
  description = "Deployment name; prefixes the role and inline-policy names."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the KOTS app installs into. The trust policy admits system:serviceaccount:<namespace>:* and nothing outside it."
  type        = string
}

variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN of the EKS cluster. Both the Federated principal and (via its :oidc-provider/ suffix) the condition-key issuer derive from this single value, so they can never disagree."
  type        = string
}

variable "crl_bucket_arn" {
  description = "ARN of the crl.<domain> bucket. Object actions are granted on <arn>/*, bucket actions on the ARN itself — pass the bare bucket ARN, never a /* form."
  type        = string
}

variable "gateway_jwt_key_arn" {
  description = "ARN of the Terraform-managed gateway JWT signing key (modules/kms), pinned explicitly in statement 3 so the wildcard sign statement can be tag-scoped later without breaking the gateway."
  type        = string
}
