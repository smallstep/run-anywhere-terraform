# The inter-stage contract. Two consumers, neither of which may be broken
# casually: workloads reads this root's state via terraform_remote_state, and
# the KOTS ConfigValues are rendered from `terraform output -json` (the README
# maps outputs to configuration items).

output "region" {
  value = var.region
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}

data "aws_caller_identity" "current" {}

output "base_domain" {
  value = var.base_domain
}

output "namespace" {
  value = var.namespace
}

output "route53_zone_id" {
  value = module.dns.zone_id
}

output "route53_name_servers" {
  description = "Delegate these in the parent zone. Nothing under the domain resolves until that happens."
  value       = module.dns.name_servers
}

# --- EKS ---------------------------------------------------------------------

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_ca_data" {
  value = module.eks.cluster_ca_data
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  value = module.eks.node_security_group_id
}

# --- Network -----------------------------------------------------------------

output "vpc_id" {
  value = module.network.vpc_id
}

output "public_subnet_ids" {
  value = module.network.public_subnet_ids
}

output "private_subnet_ids" {
  value = module.network.private_subnet_ids
}

output "lobby_eip_allocation_ids" {
  description = "One per public subnet, joined into the KOTS aws_nlb_ip config — the app's NLB annotation requires the counts to match."
  value       = module.network.lobby_eip_allocation_ids
}

output "lobby_eip_public_ips" {
  value = module.network.lobby_eip_public_ips
}

# --- IAM roles (IRSA) --------------------------------------------------------

output "lb_controller_role_arn" {
  value = module.eks.lb_controller_role_arn
}

output "ebs_csi_role_arn" {
  value = module.eks.ebs_csi_role_arn
}

output "fluent_bit_role_arn" {
  value = module.eks.fluent_bit_role_arn
}

output "bootstrap_role_arn" {
  value = module.eks.bootstrap_role_arn
}

output "app_iam_role_arn" {
  description = "The shared IRSA role every platform service account assumes — KOTS config key_management_settings.aws_cluster_iam_role."
  value       = module.iam_app.app_role_arn
}

# --- KMS ---------------------------------------------------------------------

output "platform_kms_key_arn" {
  value = module.kms.platform_key_arn
}

output "gateway_jwt_signing_key" {
  description = "Already in the awskms:key-id=<uuid> form the KOTS config expects."
  value       = module.kms.gateway_jwt_signing_key
}

output "gateway_jwt_signing_pubkey_b64" {
  value = module.kms.gateway_jwt_signing_pubkey_b64
}

# --- Data stores -------------------------------------------------------------

output "rds_host" {
  value = module.data.rds_host
}

output "rds_port" {
  value = module.data.rds_port
}

output "redis_host" {
  value = module.data.redis_host
}

output "redis_port" {
  value = module.data.redis_port
}

output "app_secret_arns" {
  description = "Secrets Manager ARNs keyed by short name (master, postgres_app, postgres_landlordcachesrv, redis_auth, auth_secret, private_issuer, majordomo_provisioner, mission_control_provisioner, kots_admin_password, smtp). Consumed by the workloads bootstrap job and the install tooling."
  value = merge(
    module.data.secret_arns,
    { smtp = module.ses_smtp.smtp_secret_arn },
  )
}

# --- CRL ---------------------------------------------------------------------

output "crl_bucket_name" {
  value = module.crl_bucket.bucket_name
}

output "crl_url" {
  value = module.crl_bucket.crl_url
}

# --- SMTP --------------------------------------------------------------------

output "smtp_host" {
  value = module.ses_smtp.smtp_host
}

output "smtp_port" {
  value = module.ses_smtp.smtp_port
}

output "smtp_username" {
  value = module.ses_smtp.smtp_username
}

# --- Logging -----------------------------------------------------------------

output "container_log_group_name" {
  description = "Empty string when enable_logging=false."
  value       = module.eks.container_log_group_name
}

