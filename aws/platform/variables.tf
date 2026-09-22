variable "name" {
  description = "Deployment name. Tags, resource names, the EKS cluster name, and the Secrets Manager prefix derive from it."
  type        = string
  default     = "smallstep"
}

variable "region" {
  description = "Region for everything except the CloudFront certificate."
  type        = string
  default     = "us-east-2"
}

variable "base_domain" {
  description = "Base domain for the platform (public zone this root creates; NS-delegated from the parent). The CRL bucket is literally named crl.<base_domain> — the KOTS app derives that, it is not configurable."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace the KOTS app installs into. The shared app IAM role's trust policy is scoped to service accounts in it."
  type        = string
  default     = "smallstep"
}

variable "create_vpc" {
  description = "true creates the VPC, subnets, NAT and S3 gateway endpoint from vpc_cidr and az_count. false uses vpc_id, public_subnet_ids and private_subnet_ids instead; the module then only tags those subnets for the load balancer controller and allocates one lobby EIP per public subnet."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "When create_vpc: pick a range that does not overlap your other networks; this VPC is not peered with anything. Private and public subnets are derived from it as /20s."
  type        = string
  default     = "10.61.0.0/16"
}

variable "az_count" {
  description = "When create_vpc: AZ spread. Three is the platform's sizing recommendation and also the number of lobby EIPs (one per public subnet — the NLB annotation requires the counts to match). With your own subnets the public subnet count plays this role."
  type        = number
  default     = 3
}

variable "single_nat_gateway" {
  description = "When create_vpc: true = one NAT gateway shared by all AZs (cheaper; a single-AZ failure takes egress with it). false = one per AZ, the production shape."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "When create_vpc = false: the VPC the cluster and data stores go in."
  type        = string
  default     = ""
}

variable "public_subnet_ids" {
  description = "When create_vpc = false: one per AZ; internet-facing load balancers land here. Each receives the kubernetes.io/role/elb tag and one lobby EIP."
  type        = list(string)
  default     = []
}

variable "private_subnet_ids" {
  description = "When create_vpc = false: EKS nodes, RDS and ElastiCache live here; they need a route to the internet (NAT) for image pulls. Each receives the kubernetes.io/role/internal-elb tag."
  type        = list(string)
  default     = []
}

variable "eks_version" {
  description = "Pinned deliberately, never floated. Also the escape hatch if the KOTS-bundled cert-manager v1.5.5 objects to a newer API surface."
  type        = string
  default     = "1.31"
}

variable "cluster_endpoint_private_only" {
  description = "true = the API server is reachable only in-VPC (kubectl and kots then need a bastion or VPN), the production shape. false keeps the public endpoint, restricted to api_public_access_cidrs."
  type        = bool
  default     = false
}

variable "api_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public endpoint when it is enabled. Set to your operator IPs; there is no permissive default on purpose."
  type        = list(string)
}

variable "eks_node_instance_type" {
  description = "Workers. m6i.xlarge = 4 vCPU / 16 GiB, the documented per-worker sizing."
  type        = string
  default     = "m6i.xlarge"
}

variable "eks_node_desired" {
  description = "6 is the documented recommendation; 3 carries the platform for evaluation."
  type        = number
  default     = 6
}

variable "eks_node_min" {
  type    = number
  default = 3
}

variable "eks_node_max" {
  type    = number
  default = 8
}

variable "db_instance_class" {
  description = "db.m6i.large is the documented sizing; db.t4g.medium carries an evaluation."
  type        = string
  default     = "db.m6i.large"
}

variable "db_multi_az" {
  description = "true = synchronous standby in a second AZ with automatic failover, the production shape."
  type        = bool
  default     = true
}

variable "db_password_version" {
  description = "Shared write-only version for every ephemeral password in modules/data. Bump to rotate; the same variable feeds both the resource and its Secrets Manager mirror so they can never disagree."
  type        = number
  default     = 1
}

variable "redis_node_type" {
  description = "cache.m6g.large is the documented sizing; cache.t4g.small carries an evaluation."
  type        = string
  default     = "cache.m6g.large"
}

variable "redis_multi_az" {
  description = "true = adds a replica + automatic failover, the production shape."
  type        = bool
  default     = true
}

variable "crl_mode" {
  description = "How http://crl.<base_domain> is served. cloudfront = private bucket + Origin Access Control + a dedicated CMK, the documented default (needs an ACM certificate in us-east-1, which the module creates; not available in GovCloud). public-bucket = S3 website hosting with a public-read policy. See modules/crl-bucket for the trade."
  type        = string
  default     = "cloudfront"

  validation {
    condition     = contains(["public-bucket", "cloudfront"], var.crl_mode)
    error_message = "crl_mode must be public-bucket or cloudfront."
  }
}

variable "smtp_mode" {
  description = "ses = real SES identity + SMTP credentials (sandbox caveats apply). dummy = placeholder values; the platform boots and invitation emails silently fail."
  type        = string
  default     = "ses"

  validation {
    condition     = contains(["ses", "dummy"], var.smtp_mode)
    error_message = "smtp_mode must be ses or dummy."
  }
}

variable "deletion_protection" {
  description = "Production posture when true: RDS deletion protection on, a final snapshot on destroy, and 7-day recovery windows on secrets. false is the evaluation posture: `terraform destroy` removes everything without leaving snapshots or scheduled-deletion secrets behind."
  type        = bool
  default     = true
}

variable "enable_logging" {
  description = "Fluent Bit -> CloudWatch Logs (JSON), for SIEM ingestion. Creates the log group and the fluent-bit IRSA role here; workloads deploys the daemonset."
  type        = bool
  default     = true
}
