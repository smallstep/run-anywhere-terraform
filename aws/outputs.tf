#---------------------------------------------------------------------------------- 
# 
# This file funtions as the source of all `output` resource types for the 
# AWS Onprem Terraform Project, ordered alphabetically.
# 
#----------------------------------------------------------------------------------

output "crl_bucket_name" {
  description = "crl.<base_domain>. The application derives the same name from the base domain."
  value       = aws_s3_bucket.veto_crls.bucket
}

output "crl_cloudfront_distribution_id" {
  description = "The distribution serving the CRL when crl_mode = cloudfront (null otherwise), for `aws cloudfront create-invalidation` when a fresh CRL must reach every edge before the cache expires."
  value       = one(aws_cloudfront_distribution.crl[*].id)
}

output "crl_url" {
  description = "Plain HTTP in both modes; CRL clients do not speak TLS to the distribution point."
  value       = "http://${trimsuffix(aws_route53_record.crl.name, ".")}"
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
}

output "eks_cluster_name" {
  value = aws_eks_cluster.eks.name
}

output "gateway_jwt_signing_key" {
  description = "Exactly the value the KOTS config item gateway_jwt_signing_key expects."
  value       = "awskms:key-id=${aws_kms_key.gateway_jwt.key_id}"
}

output "gateway_jwt_signing_pubkey_b64" {
  description = "base64(PEM) of the JWT verifying key, for the KOTS config item gateway_jwt_signing_pubkey."
  value       = base64encode(data.aws_kms_public_key.gateway_jwt.public_key_pem)
}

output "eks_kubeconfig_certificate_authority_data" {
  value = aws_eks_cluster.eks.certificate_authority[0].data
}

output "iam_service_account_arn" {
  description = "The role every platform service account assumes. Exactly the value the KOTS config item aws_cluster_iam_role expects."
  value       = aws_iam_role.eks_service_account.arn
}

output "missioncontrol_provisioner_secret_arn" {
  value = aws_secretsmanager_secret.missioncontrol_secret.arn
}

output "redis_auth_secret_arn" {
  description = "Secrets Manager ARN of the Redis AUTH token; the same value is placed in the redis-auth Kubernetes secret."
  value       = aws_secretsmanager_secret.redis_auth.arn
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

output "route53_att_domain" {
  value = trimsuffix(aws_route53_record.att.name, ".")
}

output "route53_base_domain" {
  value = trimsuffix(aws_route53_zone.cluster.name, ".")
}

output "route53_gateway_domain" {
  description = "The REST/GraphQL API host (gateway.<base>)."
  value       = trimsuffix(aws_route53_record.gateway.name, ".")
}

output "route53_gateway_api_domain" {
  description = "The web application's API ingress (gateway.api.<base>); not the REST API."
  value       = trimsuffix(aws_route53_record.web_api_gateway.name, ".")
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