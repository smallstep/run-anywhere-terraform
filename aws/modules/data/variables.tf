# Inputs are pinned by platform/main.tf — the root's module
# block is the contract, and every name here appears there verbatim. Sizing
# and HA knobs (instance class, multi-AZ) deliberately live at the root as
# variables with their production defaults; this module holds only what
# is invariant across postures.

variable "name" {
  description = "Deployment name. Resource names, tags, and the Secrets Manager prefix \"<name>/app/\" derive from it — the EKS bootstrap role's secret access is scoped to that prefix, so it must match what modules/eks was given."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the DB and cache subnet groups. Spanning multiple AZs is what makes the multi-AZ toggles below meaningful."
  type        = list(string)
}

variable "node_security_group_id" {
  description = "EKS node security group. Membership is the only path to 5432/6379 — there is no CIDR-based ingress rule anywhere in this module."
  type        = string
}

variable "kms_key_arn" {
  description = "Platform CMK (modules/kms). Encrypts RDS storage — and therefore its automated snapshots, which inherit the CMK — plus ElastiCache at rest."
  type        = string
}

variable "db_instance_class" {
  type = string
}

variable "db_multi_az" {
  description = "Synchronous standby in a second AZ with automatic failover; the production shape."
  type        = bool
}

variable "deletion_protection" {
  description = "Production posture when true: RDS deletion protection on, a final snapshot on destroy, and 7-day recovery windows on secrets. false is the evaluation posture: `terraform destroy` removes everything without leaving snapshots or scheduled-deletion secrets behind."
  type        = bool
  default     = true
}

variable "db_password_version" {
  description = "Version counter shared by EVERY write-only secret write in this module: the RDS master password, its Secrets Manager mirror, all generated app secrets, and (via keepers) the Redis auth token. A write-only argument is only re-sent when its version changes, so split versions let a partially-failed apply leave a resource and its mirror permanently disagreeing — the failure mode this module's main.tf documents. Bump to rotate everything in one apply."
  type        = number
}

variable "redis_node_type" {
  type = string
}

variable "redis_multi_az" {
  description = "Adds a replica in a second AZ plus automatic failover; the production shape."
  type        = bool
}
