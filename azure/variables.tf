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
