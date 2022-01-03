#-------------------------------------------------------------------------------------- 
# 
# This file hosts all variable resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

variable "project_id" {
  default     = "smallstep-dev"
  description = "The project ID (not name) where Terraform will apply (pre-existing)."
  type        = string
}

variable "region" {
  description = "GCP region for the project."
  type        = string
}

variable "zone" {
  description = "GCP zone for the project."
  type        = string
}

variable "base_domain" {
  description = "The base domain for all smallstep subdomains."
  type        = string
}

variable "namespace" {
  default     = "smallstep"
  description = "Kubernetes namespace where run anywhere will be installed."
  type        = string
}

variable "cloudsql_instance_tier" {
  default     = "db-g1-small"
  description = "CloudSQL desired instance size."
  type        = string
}

variable "cloudsql_enable_public_ip" {
  default     = false
  description = "Sets a publicly accessible IP address for CloudSQL instance."
  type        = bool
}

variable "cloudsql_high_availability" {
  default     = true
  description = "Sets up the databases as HA."
  type        = bool
}

variable "cloudsql_work_mem" {
  default     = 4000000
  description = "Working memory for Postgres queries."
  type        = number
}

variable "cloudsql_log_min_duration_statement" {
  default     = 250
  description = "Threshold for logging slow queries."
  type        = number
}

variable "kube_config_path" {
  default     = "~/.kube/config"
  description = "Path where kube config is stored."
  type        = string
}

variable "k8s_channel" {
  default     = "REGULAR"
  description = "Kubernetes release channel."
  type        = string
}

variable "node_machine_type" {
  default     = "e2-standard-2"
  description = "Node type for kubernetes nodes"
  type        = string
}