output "role_arn" {
  description = "Goes into the KOTS config as https_settings.acme_dns01_aws_role_arn; the app annotates the cert-manager service account with it."
  value       = aws_iam_role.cert_manager.arn
}
