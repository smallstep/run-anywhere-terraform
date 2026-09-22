output "platform_key_arn" {
  description = "ARN of the symmetric platform key. RDS, ElastiCache, Secrets Manager, EKS envelope encryption, EBS, and the CloudWatch log group all take this."
  value       = aws_kms_key.platform.arn
}

output "platform_key_id" {
  description = "Key UUID, for the few callers (EBS launch templates, CLI checks) that want the id rather than the ARN."
  value       = aws_kms_key.platform.key_id
}

output "gateway_jwt_key_arn" {
  description = "ARN of the asymmetric JWT signing key — modules/iam-app pins its explicit Sign/GetPublicKey/DescribeKey statement to this."
  value       = aws_kms_key.gateway_jwt.arn
}

output "gateway_jwt_signing_key" {
  description = "EXACTLY the form the KOTS config expects for key_management_settings.gateway_jwt_signing_key — it is pasted in verbatim, do not decorate it."
  value       = "awskms:key-id=${aws_kms_key.gateway_jwt.key_id}"
}

output "gateway_jwt_signing_pubkey_b64" {
  description = "base64(PEM) of the JWT verifying key, for KOTS config consumption."
  value       = base64encode(data.aws_kms_public_key.gateway_jwt.public_key_pem)
}
