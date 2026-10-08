variable "name" {
  description = "Deployment name; prefixes the role and inline-policy names."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the KOTS app installs into. KOTS deploys its Helm charts there too, so this is cert-manager's namespace."
  type        = string
}

variable "service_account" {
  description = "cert-manager's controller service account, the only subject the trust policy admits. The chart names it after its release (cert-manager); change it only if the chart's serviceAccount.name is overridden."
  type        = string
  default     = "cert-manager"
}

variable "oidc_provider_arn" {
  description = "IAM OIDC provider ARN of the EKS cluster — same single-source derivation as modules/iam-app."
  type        = string
}

variable "zone_id" {
  description = "The Route 53 hosted zone that serves the base domain. Record changes are granted on this zone and nothing else."
  type        = string
}
