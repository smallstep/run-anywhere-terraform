#----------------------------------------------------------------------------------
#
# The CRL distribution point.
#
# The platform's CRL distributor writes revocation lists to s3://crl.<base_domain>
# (the application derives that bucket name from the base domain; it is not
# configurable), and every certificate it issues names
# http://crl.<base_domain>/<file> as its CRL Distribution Point. Validators fetch
# that URL anonymously over plain HTTP — a client cannot be required to complete
# a TLS handshake to check revocation of the very certificate the handshake
# would depend on, which is why every public CA distributes CRLs over HTTP. A
# private bucket with SSE-KMS refuses those fetches twice over (no public policy,
# and an anonymous principal holds no kms:Decrypt), so revocation checking
# silently never happens.
#
# var.crl_mode selects one of two complete shapes for the same bucket:
#
#   cloudfront     The bucket stays private (Block Public Access on, SSE-KMS
#                  under the dedicated key in cloudfront.tf) and a CloudFront
#                  distribution with Origin Access Control is its only reader.
#                  Plain HTTP is served at the edge. Objects appear at every
#                  edge only once the cache TTL expires; CRLs carry their own
#                  freshness (nextUpdate) so that is normally fine, and
#                  `aws cloudfront create-invalidation --paths '/*'` is the
#                  manual override.
#   public-bucket  S3 website hosting, a public-read bucket policy, SSE-S3. The
#                  one deliberately public bucket in the deployment. Objects
#                  are served the moment they are written.
#
# ACLs are disabled on both buckets (BucketOwnerEnforced): S3 has created every
# new bucket that way since 2023, and any access grant comes from a bucket
# policy, never from per-object ACLs.
#
#----------------------------------------------------------------------------------

locals {
  crl_fqdn       = "crl.${aws_route53_zone.cluster.name}"
  crl_cloudfront = var.crl_mode == "cloudfront"
}

resource "aws_s3_bucket" "veto_crls" {
  bucket = local.crl_fqdn
}

resource "aws_s3_bucket_ownership_controls" "veto_crls" {
  bucket = aws_s3_bucket.veto_crls.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "veto_crls" {
  bucket = aws_s3_bucket.veto_crls.id
  versioning_configuration {
    status = "Enabled"
  }
}

# All four on in cloudfront mode; all four off in public-bucket mode, for this
# bucket only. This is the BUCKET-level block: if the ACCOUNT-level S3 Block
# Public Access is enabled, the public-read policy below is rejected regardless
# of what is set here, and cloudfront mode is the only option.
resource "aws_s3_bucket_public_access_block" "veto_crls" {
  bucket                  = aws_s3_bucket.veto_crls.id
  block_public_acls       = local.crl_cloudfront
  block_public_policy     = local.crl_cloudfront
  restrict_public_buckets = local.crl_cloudfront
  ignore_public_acls      = local.crl_cloudfront
}

# SSE-S3 in public-bucket mode, never SSE-KMS: decrypting a KMS-encrypted object
# requires kms:Decrypt on the key, and an anonymous principal has no permissions
# at all. In cloudfront mode the objects are encrypted under the dedicated key
# whose policy admits the CloudFront service principal (cloudfront.tf).
resource "aws_s3_bucket_server_side_encryption_configuration" "veto_crls" {
  bucket = aws_s3_bucket.veto_crls.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.crl_cloudfront ? "aws:kms" : "AES256"
      kms_master_key_id = local.crl_cloudfront ? one(aws_kms_key.crl[*].arn) : null
    }
  }
}

# --- public-bucket mode -----------------------------------------------------------

# S3 rejects a public bucket policy while BlockPublicPolicy is still on, and
# Terraform has no implicit ordering between these two resources — the
# dependency must be spelled out or fresh applies fail intermittently.
resource "aws_s3_bucket_policy" "veto_crls_public" {
  count  = local.crl_cloudfront ? 0 : 1
  bucket = aws_s3_bucket.veto_crls.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AnonymousCRLRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.veto_crls.arn}/*"
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.veto_crls]
}

# The website endpoint is what serves plain HTTP (the REST endpoint is
# HTTPS-biased and path-styled). Website hosting routes virtual-hosted: S3 picks
# the bucket whose NAME equals the Host header, which is why the bucket must be
# named exactly crl.<base_domain>. index_document is required by the API;
# nothing ever fetches it.
resource "aws_s3_bucket_website_configuration" "veto_crls" {
  count  = local.crl_cloudfront ? 0 : 1
  bucket = aws_s3_bucket.veto_crls.id

  index_document {
    suffix = "index.html"
  }
}

# --- Access logs for the CRL bucket ------------------------------------------------
#
# S3 delivers server access logs only to a target bucket encrypted with SSE-S3;
# a target with SSE-KMS default encryption receives nothing. Delivery is
# authorized by bucket policy (the logging.s3.amazonaws.com service principal),
# which is the shape that works with ACLs disabled.

#tfsec:ignore:aws-s3-enable-bucket-logging
resource "aws_s3_bucket" "log_bucket" {
  bucket = "${local.crl_fqdn}-log-bucket"
}

resource "aws_s3_bucket_ownership_controls" "log_bucket" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "log_bucket" {
  bucket = aws_s3_bucket.log_bucket.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "logbucket" {
  bucket                  = aws_s3_bucket.log_bucket.id
  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true
  ignore_public_acls      = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_bucket" {
  bucket = aws_s3_bucket.log_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "log_bucket" {
  bucket = aws_s3_bucket.log_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "S3ServerAccessLogsPolicy"
        Effect    = "Allow"
        Principal = { Service = "logging.s3.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.log_bucket.arn}/log/*"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_s3_bucket.veto_crls.arn
          }
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.logbucket]
}

resource "aws_s3_bucket_logging" "veto_crls" {
  bucket = aws_s3_bucket.veto_crls.id

  target_bucket = aws_s3_bucket.log_bucket.id
  target_prefix = "log/"

  depends_on = [aws_s3_bucket_policy.log_bucket]
}
