# Inputs are wired exclusively from platform/main.tf; the descriptions
# below carry the constraints the types cannot.

variable "name" {
  description = "Deployment name. Becomes the cluster name verbatim, the IRSA role-name prefix, and the log-group prefix the KMS key policy is scoped to."
  type        = string
}

variable "cluster_version" {
  description = "EKS Kubernetes version, pinned — never floated. The escape hatch if the KOTS-bundled cert-manager v1.5.5 objects to a newer API surface."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Subnets for the control-plane ENIs and the node group. Private on purpose: nodes reach the world through NAT, never the other way around."
  type        = list(string)
}

variable "cluster_endpoint_private_only" {
  description = "true = the API server is reachable only in-VPC (kubectl and kots then need a bastion or VPN), the production shape. false keeps the public endpoint, restricted to api_public_access_cidrs."
  type        = bool
}

variable "api_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint while it exists. Ignored by AWS once the endpoint goes private-only."
  type        = list(string)
}

variable "node_instance_type" {
  type = string
}

variable "node_desired" {
  type = number
}

variable "node_min" {
  type = number
}

variable "node_max" {
  type = number
}

variable "kms_key_arn" {
  description = "The platform CMK (modules/kms). Encrypts cluster secrets, node root volumes, and the container log group — one key, one audit trail."
  type        = string
}

variable "enable_logging" {
  description = "Gates the container log group and the fluent-bit IRSA role. Off means the corresponding outputs are empty strings, a shape workloads relies on."
  type        = bool
}

variable "namespace" {
  description = "Namespace the KOTS app installs into. The bootstrap role's trust policy is scoped to <namespace>:smallstep-bootstrap and nothing else."
  type        = string
}

variable "app_secrets_prefix" {
  description = "Secrets Manager name prefix (\"<name>/app\") the bootstrap role may read under. Must match what modules/data names its secrets, or the bootstrap job gets AccessDenied with everything looking correct."
  type        = string
}
