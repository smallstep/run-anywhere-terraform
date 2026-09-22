variable "domain" {
  description = "Base domain. The bucket is literally named crl.<domain> — the KOTS app derives that name from the base domain; it is not configurable here or in the app."
  type        = string
}

variable "zone_id" {
  description = "Route 53 zone for <domain>. Receives the crl.<domain> A record and, in cloudfront mode, the ACM DNS-validation records."
  type        = string
}

variable "crl_mode" {
  description = "public-bucket = the product's expected shape (anonymous plain-HTTP fetch from S3 website hosting). cloudfront = private bucket behind a distribution, the no-public-buckets posture. The header of main.tf records the trade."
  type        = string

  validation {
    condition     = contains(["public-bucket", "cloudfront"], var.crl_mode)
    error_message = "crl_mode must be public-bucket or cloudfront."
  }
}

variable "kms_key_arn" {
  description = "Platform CMK. Accepted because the root passes it to every module that stores data, and deliberately UNUSED by both modes: public-bucket must be SSE-S3 (KMS-encrypted objects 403 every anonymous GET), and cloudfront mode creates its own key so the CloudFront service-principal grant never has to be spliced into the platform key's policy in modules/kms."
  type        = string
}

variable "deletion_protection" {
  description = "Production posture when true: RDS deletion protection on, a final snapshot on destroy, and 7-day recovery windows on secrets. false is the evaluation posture: `terraform destroy` removes everything without leaving snapshots or scheduled-deletion secrets behind."
  type        = bool
  default     = true
}
