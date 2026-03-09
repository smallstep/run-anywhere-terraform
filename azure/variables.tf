variable "base_domain" {
  description = "The base domain for all smallstep subdomains."
  type        = string
}

variable "resource_group_name" {
  default     = "smallstep-onprem"
  description = "Name for the Resource Group created by the module."
  type        = string
}

variable "resource_group_location" {
  default     = "Central US"
  description = "Location for the Resource Group created by the module."
  type        = string
}

variable "k8s_cluster_name" {
  default     = "smallstep"
  description = "Name for the AKS cluster created by the module."
  type        = string
}

variable "namespace" {
  default     = "smallstep"
  description = "Kubernetes namespace where the Smallstep application will be installed."
  type        = string
}

variable "private_issuer_password" {
  description = "The private issuer password."
  type        = string
  sensitive   = true
}

# This must be AT LEAST 6
variable "redis_version" {
  default     = 6
  description = "The version of Redis to run."
  type        = number
}

variable "smtp_password" {
  description = "The SMTP password."
  type        = string
  sensitive   = true
}

variable "yubihsm_pin" {
  description = "Yubi HSM pin"
  type        = string
  sensitive   = true
}

variable "yubihsm_enabled" {
  description = "Yubi HSM enabled"
  type        = bool
}

variable "oidc_jwks" {
  description = <<-EOT
    OIDC signing JWKS (private key set, JSON). Required on first apply; ignored on subsequent applies.

    Preferred: run scripts/create_oidc_secret.sh (after Key Vault exists) to generate and
    store the JWKS directly in Key Vault, then apply with this variable left blank.

    Alternative: generate with the command in scripts/create_oidc_secret.sh and pass as
    TF_VAR_oidc_jwks="..." on first apply.
  EOT
  type      = string
  sensitive = true
  default   = ""
}

variable "node_count" {
  default     = 5
  description = "Number of nodes in the default AKS node pool."
  type        = number
}
