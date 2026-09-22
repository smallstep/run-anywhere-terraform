output "bucket_name" {
  description = "Always literally crl.<domain> in both modes — the KOTS app derives this name from the base domain, and veto writes to it unconditionally."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "Consumed by modules/iam-app to grant the platform role its write path."
  value       = aws_s3_bucket.this.arn
}

output "crl_url" {
  description = "Plain HTTP in both modes — see the header of main.tf for why validators cannot be made to speak TLS here. In cloudfront mode the distribution accepts HTTP (viewer_protocol_policy allow-all), so the URL does not change with the mode."
  value       = "http://${local.fqdn}"
}
