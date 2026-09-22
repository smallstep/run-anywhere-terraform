# Same shape in both modes on purpose: the KOTS config renderer and the
# workloads bootstrap job consume these without knowing which mode built
# them. The password is never an output — it travels only inside the secret.

output "smtp_host" {
  description = "email-smtp.<region>.amazonaws.com in ses mode; smtp.invalid in dummy mode."
  value       = local.smtp_host
}

output "smtp_port" {
  description = "587 (STARTTLS submission) in both modes."
  value       = 587
}

output "smtp_username" {
  description = "The IAM access key id in ses mode (an access key id is an identifier, not a secret); the literal string dummy otherwise."
  value       = local.smtp_username
}

output "smtp_secret_arn" {
  description = "Secrets Manager ARN of <name>/app/smtp holding {username, password}."
  value       = aws_secretsmanager_secret.smtp.arn
}
