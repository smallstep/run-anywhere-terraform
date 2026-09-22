variable "name" {
  description = "Deployment name. Both key aliases, the resource tags, and — load-bearing — the CloudWatch Logs EncryptionContext ArnLike pattern derive from it, so it must match the name the eks module uses to name /<name>/eks/containers."
  type        = string
}

variable "deletion_protection" {
  description = "Production posture when true: RDS deletion protection on, a final snapshot on destroy, and 7-day recovery windows on secrets. false is the evaluation posture: `terraform destroy` removes everything without leaving snapshots or scheduled-deletion secrets behind."
  type        = bool
  default     = true
}
