#---------------------------------------------------------------------------------- 
# 
# This file funtions as the source of all `output` resource types for the 
# AWS Onprem Terraform Project, ordered alphabetically.
# 
#----------------------------------------------------------------------------------

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "eks_kubeconfig_certificate_authority_data" {
  value = aws_eks_cluster.eks.certificate_authority[0].data
}

output "iam_service_account_arn" {
  value = aws_iam_role.eks_service_account.arn
}

output "ingress_eip" {
  value = concat(aws_eip.cluster[*].id)
}

output "rds_cluster_endpoint" {
  value = aws_rds_cluster.smallstep.endpoint
}

output "rds_cluster_port" {
  value = aws_rds_cluster.smallstep.port
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  value = aws_elasticache_replication_group.redis.port
}

output "route53_api_domain" {
  value = trimsuffix(aws_route53_record.web_api.name, ".")
}

output "route53_base_domain" {
  value = trimsuffix(aws_route53_zone.cluster.name, ".")
}

output "route53_gateway_domain" {
  value = trimsuffix(aws_route53_record.web_api_gateway.name, ".")
}

output "route53_linkedca_api_domain" {
  value = trimsuffix(aws_route53_record.linkedca_api.name, ".")
}

output "route53_name_servers" {
  value = aws_route53_zone.cluster.name_servers
}

output "route53_scim_domain" {
  value = trimsuffix(aws_route53_record.web_api_scim.name, ".")
}

output "route53_zone" {
  value = aws_route53_zone.cluster.name
}