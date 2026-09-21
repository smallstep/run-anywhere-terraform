#--------------------------------------------------------------------------------------
#
# This file hosts all variable resources for the AWS Run Anywhere deployment.
#
#--------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------
#                                !!! IMPORTANT !!!
# -------------------------------------------------------------------------------------
# When running first apply set: terraform apply -var smtp_password="<value>" \
#                                               -var private_issuer_password="<value>"
#
#                                               (Optional)
#                                               (if you set `yubihsm_enabled = true`) \
#                                               -var yubihsm_pin="<value"
# -------------------------------------------------------------------------------------
# Subsequent applies will not require you to set these variables, as changes
# will be ignored.
# -------------------------------------------------------------------------------------

variable "backup_retention_period" {
  default     = 7
  description = "Number of days to retain logs and grace period for deleting secrets/keys."
  type        = number
}

variable "base_domain" {
  description = "The base domain for all project subdomains."
  type        = string
}

variable "default_description" {
  default     = "Terraform - Do not modify by hand."
  description = "Description tag assigned to each Terraform resource."
  type        = string
}

variable "default_name" {
  default     = "run-anywhere-terraform"
  description = "The default naming convention for each Terraform resource."
  type        = string
}

variable "k8s_alb_controller_version" {
  default     = "2.4.4"
  description = "Version of the aws-load-balancer-controller to run in the cluster."
  type        = string
}

# https://aws.amazon.com/ec2/instance-types/
variable "k8s_instance_types" {
  default     = ["t3.large"]
  description = "List of instance types desired for the EKS cluster."
  type        = list(string)
}

variable "k8s_kube_config_path" {
  default     = "~/.kube/config"
  description = "Local path for your EKS kube config."
  type        = string
}

variable "k8s_namespace" {
  default     = "smallstep"
  description = "Namespace in the EKS cluster where the CA pods where deploy."
  type        = string
}

variable "k8s_pool_desired" {
  default     = 6
  description = "Desired number of instances for the EKS Node Pool."
  type        = number
}

variable "k8s_pool_max" {
  default     = 10
  description = "Maximum number of instances for the EKS Node Pool."
  type        = number
}

variable "k8s_pool_min" {
  default     = 3
  description = "Minimum number of instances for the EKS Node Pool."
  type        = number
}

variable "private_issuer_password" {
  description = "The private issuer password used by the create_secrets.sh script."
  default     = ""
  type        = string
  sensitive   = true
}

variable "redis_cache_clusters" {
  default     = 2
  description = "Number of caches clusters for the Redis instance."
  type        = number
}

# https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/ParameterGroups.Redis.html
variable "redis_desired_params" {
  default     = []
  description = "List of map of desired Redis Elasticache parameters for the Redis instance."
  type        = list(map(string))

  /*
    For example:

    var.redis_desired_params = [
      {
        name  = "client-output-buffer-limit-replica-hard-limit"
        value = "4096"
      },
      {
        name  = "min-replicas-max-lag"
        value = "12"
      }
    ]
  */
}

# Must be AT LEAST "6.2"
variable "redis_engine_version" {
  default     = "6.x"
  description = "Desired engine version for the Redis instance."
  type        = string
}

# Must be AT LEAST "redis6.0"
variable "redis_family" {
  default     = "redis6.x"
  description = "Desired family for the Redis instance."
  type        = string
}

variable "redis_max_memory_policy" {
  default     = "volatile-lru"
  description = "Permitted values: allkeys-lru, volatile-lru, allkeys-lfu, volatile-lfu, allkeys-random, volatile-random, noeviction"
  type        = string
}

# https://docs.aws.amazon.com/AmazonElastiCache/latest/red-ug/CacheNodes.SupportedTypes.html
variable "redis_node_type" {
  default     = "cache.m5.large"
  description = "Node type for the Redis instance."
  type        = string
}

variable "redis_port" {
  default     = 6379
  description = "Port used to access the Redis instance."
  type        = number
}

variable "redis_timeout" {
  default     = 300
  description = "Timeout interval (in seconds) for Redis instance connections."
  type        = number
}

# https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/AuroraPostgreSQL.Reference.html
variable "rds_desired_params" {
  default     = []
  description = "List of map of desired RDS parameters for the Aurora cluster."
  type        = list(map(string))

  /*
    For example:

    var.rds_desired_params = [
      {
        name  = "work_mem"
        value = "50000"
      },
      {
        name  = "auto_explain.log_triggers"
        value = "1"
      }
    ]
  */
}

variable "rds_enable_cloudwatch_logging" {
  default     = true
  description = "If CoudWatch logging is enabled for the Aurora Cluster."
  type        = bool
}

variable "rds_engine_version" {
  default     = "16.4"
  description = "Aurora PostgreSQL engine version. The platform requires PostgreSQL 14 or newer."
  type        = string

  validation {
    condition     = tonumber(split(".", var.rds_engine_version)[0]) >= 14
    error_message = "The platform requires PostgreSQL 14 or newer."
  }
}

variable "rds_instance_count" {
  default     = 2
  description = "Number of aws_cluster_instances in the Aurora cluster."
  type        = number
}

#  https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.DBInstanceClass.html
variable "rds_instance_class" {
  default     = "db.r6g.large"
  description = "Desired instance class for our Aurora cluster."
  type        = string
}

variable "rds_master_username" {
  default     = "postgres"
  description = "Username granted to the administrative user for the Aurora cluster."
  type        = string
}

variable "rds_port" {
  default     = 5432
  description = "Port used to access the Aurora cluster."
  type        = number
}

variable "rds_transaction_timeout" {
  default     = 300000
  description = "Timeout period (milliseconds) for any connection to the Aurora cluster - prevents hanging connections."
  type        = number
}

variable "region" {
  description = "AWS region used by all project resources."
  type        = string
}

variable "eks_version" {
  default     = "1.31"
  description = "Kubernetes version for the EKS cluster. Pinned so an EKS default bump cannot retire an API the bundled components still use; change it deliberately."
  type        = string
}

variable "cluster_endpoint_private_only" {
  default     = false
  description = "When true the EKS API endpoint is reachable only from inside the VPC; kubectl and the kots CLI then need a bastion or VPN. When false, access is limited to security_groups_cidr_blocks, which must then be non-empty."
  type        = bool
}

variable "node_root_volume_size" {
  default     = 100
  description = "Root volume size in GiB for worker nodes. Encrypted with the project KMS key via a launch template."
  type        = number
}

variable "linkerd_inject" {
  default     = false
  description = "Annotate the application namespace for Linkerd proxy injection. The current release does not require a service mesh; leave false unless you run Linkerd deliberately."
  type        = bool
}

variable "security_groups_cidr_blocks" {
  default     = []
  description = "Operator CIDR ranges allowed to reach the EKS API endpoint (and the base security group rules). Required unless cluster_endpoint_private_only is true: an empty list with a public endpoint would otherwise be open to the internet."
  type        = list(string)

  validation {
    condition     = var.cluster_endpoint_private_only || length(var.security_groups_cidr_blocks) > 0
    error_message = "security_groups_cidr_blocks must list the operator ranges when the EKS endpoint is public; set cluster_endpoint_private_only = true to have no public endpoint."
  }
}

variable "smtp_password" {
  description = "The SMTP password used by the create_secrets.sh script."
  default     = ""
  type        = string
  sensitive   = true
}

variable "vpc" {
  description = "AWS vpc used by all project resources."
  type        = string
}

variable "subnets_private" {
  description = "List of private subnets used by project compute resources. Must either have a NAT gateway or appropriate VPC Endpoints."
  type        = list(string)

  validation {
    condition     = length(var.subnets_private) > 1
    error_message = "Must use 2 or more private subnets."
  }
}

variable "subnets_public" {
  description = "List of public subnets used by NLB for the project. One Elastic IP is allocated per public subnet, so this list must be the same length as subnets_private."
  type        = list(string)

  validation {
    condition     = length(var.subnets_public) > 1
    error_message = "Must use 2 or more public subnets."
  }

  validation {
    condition     = length(var.subnets_public) == length(var.subnets_private)
    error_message = "subnets_public and subnets_private must have the same number of entries."
  }
}

variable "yubihsm_enabled" {
  default     = false
  description = "If the CA keys used are backed by a YubiHSM2, set to true."
  type        = bool
}

variable "yubihsm_pin" {
  description = "The PIN used for your HSMs, only used when setting up with HSM support."
  default     = ""
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("(^0x[0-9A-Fa-f]{4}.*$)|^$", var.yubihsm_pin))
    error_message = "Must provide a 4 digit pin in hexadecimal proceeded with the password."
  }
}


