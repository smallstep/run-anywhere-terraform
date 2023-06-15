#----------------------------------------------------------------------------------
#
# Variables to create basic rules that should be available in all Security Groups
#
#----------------------------------------------------------------------------------

variable "security_group_id" {
  description = "Security group to which we are attaching the base rules."
  type        = string
}

variable "vpc" {
  description = "VPC ID"
  type        = string
}

variable "security_groups_cidr_blocks" {
  default     = []
  description = "Security groups for the module can be set to allow ingress and egress traffic"
  type        = list(string)
}
