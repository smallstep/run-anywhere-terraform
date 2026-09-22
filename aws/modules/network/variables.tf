variable "name" {
  description = "Deployment name, used as a name prefix."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR. Private and public subnets are both derived from it as /20s."
  type        = string
}

variable "az_count" {
  description = "Availability zones to span. Also the number of lobby EIPs — the NLB annotation requires one EIP per public subnet, so these must move together."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "One NAT gateway shared by all AZs instead of one per AZ. Cheaper; a single-AZ failure then takes egress with it. Production should be false."
  type        = bool
  default     = true
}

variable "create_vpc" {
  description = "true creates the VPC from vpc_cidr and az_count. false uses vpc_id, public_subnet_ids and private_subnet_ids and touches nothing about them but the load balancer role tags."
  type        = bool
  default     = true
}

variable "vpc_id" {
  description = "When create_vpc = false: the existing VPC."
  type        = string
  default     = ""

  validation {
    condition     = var.create_vpc || var.vpc_id != ""
    error_message = "vpc_id is required when create_vpc = false."
  }
}

variable "public_subnet_ids" {
  description = "When create_vpc = false: one per AZ. Each gets the kubernetes.io/role/elb tag and one lobby EIP."
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.public_subnet_ids) > 0
    error_message = "public_subnet_ids is required when create_vpc = false."
  }
}

variable "private_subnet_ids" {
  description = "When create_vpc = false: where EKS nodes, RDS and ElastiCache live. Each gets the kubernetes.io/role/internal-elb tag."
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_vpc || length(var.private_subnet_ids) > 0
    error_message = "private_subnet_ids is required when create_vpc = false."
  }
}
