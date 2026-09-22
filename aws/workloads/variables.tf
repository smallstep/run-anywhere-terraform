variable "state_bucket" {
  description = "The Terraform state bucket; this root reads platform's outputs from it."
  type        = string
}

variable "state_region" {
  type    = string
  default = "us-east-2"
}

variable "platform_state_key" {
  description = "The platform root's state object in that bucket — its backend.hcl `key`."
  type        = string
  default     = "platform.tfstate"
}

# Chart versions are pinned here, on purpose, where a human bumping them will
# see them in a plan diff.

variable "lb_controller_chart_version" {
  description = "eks/aws-load-balancer-controller chart. The KOTS app's lobby Service is annotated for this controller (external NLB, ip targets, EIP allocations); it must be healthy before kots-install."
  type        = string
  default     = "1.8.4"
}

variable "fluent_bit_chart_version" {
  description = "aws/aws-for-fluent-bit chart."
  type        = string
  default     = "0.1.34"
}
