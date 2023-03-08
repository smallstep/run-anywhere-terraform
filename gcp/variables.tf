#-------------------------------------------------------------------------------------- 
# 
# This file hosts all variable resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

variable "base_domain" {
  description = "The base domain for all smallstep subdomains."
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

# Setting this will override the name variable for the database
variable "db_name" {
  default     = ""
  description = "Name assigned to the PostgreSQL database sitting behind the cluster."
  type        = string
}

variable "key_name" {
  default     = "terraform-secret"
  description = "Desired name for the key that will encrypt project secrets."
  type        = string
}

variable "keyring_name" {
  default     = "smallstep-terraform"
  description = "Desired name for the keyring used for project secrets."
  type        = string
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

# Setting this will override the name variable for the cluster
variable "k8s_cluster_name" {
  default     = ""
  description = "Name for the GKE cluster created by the module."
  type        = string
}

variable "namespace" {
  default     = "smallstep"
  description = "Kubernetes namespace where run anywhere will be installed."
  type        = string
}

variable "node_count" {
  default     = 2
  description = "Desired number of nodes to run in the K8s node pool."
  type        = number
}

variable "node_auto_repair" {
  default     = true
  description = "Marking 'true' will enable auto repairing on the K8s cluster."
  type        = bool
}

variable "node_auto_upgrade" {
  default     = true
  description = "Marking 'true' will enable auto upgrading on the K8s cluster."
  type        = bool
}

variable "node_machine_type" {
  default     = "e2-standard-2"
  description = "Node type for kubernetes nodes."
  type        = string
}

variable "node_max_surge_count" {
  default     = 5
  description = "The max surge count for the K8s upgrade settings."
  type        = number
}

variable "node_max_unavailable" {
  default     = 0
  description = "Max number of unavailable K8s nodes allowed for upgrade settings."
  type        = string
}

variable "path_to_secrets" {
  description = "Relative path to the generated, encrypted secrets for this module."
  type        = string
}

variable "project_id" {
  description = "The project ID (not name) where Terraform will apply (pre-existing)."
  type        = string
}

# run anywhere requires a minimum Redis version of 6.2
variable "redis_version" {
  default     = "REDIS_6_X"
  description = "Version of Redis used for the `run anywhere` deployment."
  type        = string
}

variable "redis_tier" {
  default     = "BASIC"
  description = "Redis tier used for the `run anywhere` deployment."
  type        = string
}

variable "redis_memory_size_gb" {
  default     = 1
  description = "Amount of memory assigned to Redis for the `run anywhere` deployment."
  type        = number
}

variable "region" {
  description = "GCP region for the project."
  type        = string
}

variable "name" {
  default     = "smallstep"
  description = "Optional name overriding all names for module resources."
  type        = string
}

variable "sql_database_version" {
  default     = "POSTGRES_11"
  description = "Version of PostgreSQL to run for the DB cluster."
  type        = string
}

variable "zone" {
  description = "GCP zone for the project."
  type        = string
}

# If false, then you'll have to add output.reserved_peering_ranges
# to your servicenetworking google_service_networking_connection.
# 
# Should be changed to false and managed externally if there are other
# service networking connections in place.
# ie. another instantiation of this module
variable "managed_servicenetworking" {
  default     = true
  description = "If module manages connection to servicenetworking"
}