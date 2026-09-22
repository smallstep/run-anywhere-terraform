output "app_role_arn" {
  description = "The shared IRSA role ARN — goes into the KOTS config as key_management_settings.aws_cluster_iam_role, and from there onto ~13 platform service accounts as their eks.amazonaws.com/role-arn annotation."
  value       = aws_iam_role.app.arn
}
