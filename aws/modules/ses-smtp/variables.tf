variable "name" {
  description = "Prefixes the IAM user name and the Secrets Manager secret name (<name>/app/smtp — part of the app_secret_arns contract the workloads bootstrap job consumes)."
  type        = string
}

variable "domain" {
  description = "Domain to verify as an SES sending identity. The same delegated zone the platform lives under, so DKIM CNAMEs land where SES can see them."
  type        = string
}

variable "zone_id" {
  description = "Route 53 zone for <domain>; receives the three Easy DKIM CNAME records in ses mode."
  type        = string
}

variable "deletion_protection" {
  description = "Production posture when true: RDS deletion protection on, a final snapshot on destroy, and 7-day recovery windows on secrets. false is the evaluation posture: `terraform destroy` removes everything without leaving snapshots or scheduled-deletion secrets behind."
  type        = bool
  default     = true
}

variable "smtp_mode" {
  description = "ses = real SES identity + SMTP credentials (sandbox caveats — see the header of main.tf). dummy = placeholder values; the platform boots and invitation emails fail visibly in courier's logs."
  type        = string

  validation {
    condition     = contains(["ses", "dummy"], var.smtp_mode)
    error_message = "smtp_mode must be ses or dummy."
  }
}

variable "kms_key_arn" {
  description = "Platform CMK encrypting the smtp secret in Secrets Manager."
  type        = string
}
