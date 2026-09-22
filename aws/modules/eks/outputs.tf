# Everything platform re-exports to remote-state consumers. The gated
# outputs (fluent_bit_role_arn, container_log_group_name) return empty strings
# rather than null when enable_logging=false: workloads renders Helm values
# from these through `terraform output -json`, and "" is a value a template
# can test for — null is a value that changes the output's type.

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_ca_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "IRSA provider ARN. Service-account roles created outside this module (modules/iam-app) trust this."
  value       = module.eks.oidc_provider_arn
}

output "node_security_group_id" {
  description = "Attached to every node. modules/data grants this SG ingress to PostgreSQL and Redis rather than opening CIDR ranges."
  value       = module.eks.node_security_group_id
}

output "lb_controller_role_arn" {
  value = module.lb_controller_irsa.iam_role_arn
}

output "ebs_csi_role_arn" {
  value = module.ebs_csi_irsa.iam_role_arn
}

output "fluent_bit_role_arn" {
  description = "Empty string when enable_logging=false."
  value       = var.enable_logging ? module.fluent_bit_irsa[0].iam_role_arn : ""
}


output "bootstrap_role_arn" {
  value = module.bootstrap_irsa.iam_role_arn
}

output "container_log_group_name" {
  description = "Empty string when enable_logging=false."
  value       = var.enable_logging ? aws_cloudwatch_log_group.containers[0].name : ""
}
