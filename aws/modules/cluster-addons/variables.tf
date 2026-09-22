variable "name" {
  description = "Deployment name, part of the root's module contract. Kept for labeling parity with the other modules even where no resource consumes it."
  type        = string
}

variable "region" {
  description = "AWS region, passed to the controllers as chart values — supplied explicitly so neither needs to discover it from IMDS at run time."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name. The load balancer controller tags every NLB it creates with this."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster's subnets live in. Chart value for the load balancer controller (same IMDS-avoidance reasoning as region)."
  type        = string
}

variable "kms_key_arn" {
  description = "Platform CMK ARN, baked into the gp3 default StorageClass as kmsKeyId. Without it, encrypted=\"true\" silently falls back to the AWS-managed aws/ebs key and dynamically provisioned PVCs escape the platform-CMK posture."
  type        = string
}

variable "lb_controller_role_arn" {
  description = "IRSA role for the load balancer controller. Its trust policy pins kube-system:aws-load-balancer-controller, so the service account name below is not a free choice."
  type        = string
}

variable "lb_controller_chart_version" {
  description = "eks/aws-load-balancer-controller chart version. Pinned in the root's variables.tf where a bump shows up in a plan diff."
  type        = string
}

variable "fluent_bit_role_arn" {
  description = "IRSA role for fluent-bit. Trust policy pins kube-system:fluent-bit. Unused (but still required) when logging is disabled."
  type        = string
}

variable "fluent_bit_chart_version" {
  description = "aws/aws-for-fluent-bit chart version, pinned in the root."
  type        = string
}

variable "container_log_group_name" {
  description = "CloudWatch log group for container logs. Empty string means stage 1 was applied with enable_logging=false, and the fluent-bit release is skipped entirely."
  type        = string
}
