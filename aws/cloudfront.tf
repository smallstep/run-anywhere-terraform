#----------------------------------------------------------------------------------
#
# crl_mode = "cloudfront": a private CRL bucket read only by a CloudFront
# distribution. Nothing in this file exists in public-bucket mode. The bucket
# itself, its access block, and its encryption configuration are in s3.tf; the
# crl.<base_domain> record is in dns.tf.
#
# The pieces, in dependency order: a dedicated KMS key for the objects (the
# CloudFront service principal must be able to decrypt them, and that grant is
# kept off the project key in secrets.tf); an Origin Access Control; an ACM
# certificate in us-east-1 — CloudFront accepts no other region — validated by
# DNS in the zone; the distribution; and a bucket policy admitting exactly that
# distribution.
#
#----------------------------------------------------------------------------------

locals {
  crl_cloudfront_count = local.crl_cloudfront ? 1 : 0
}

resource "aws_kms_key" "crl" {
  count = local.crl_cloudfront_count

  description         = "${local.crl_fqdn} CRL objects (CloudFront origin)"
  key_usage           = "ENCRYPT_DECRYPT"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Root delegation; without it the key is unmanageable the moment the
      # applying role changes, and IAM policies on the key stop working.
      {
        Sid       = "EnableIAMDelegation"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      # CloudFront must decrypt origin objects to serve them. The SourceArn is
      # a wildcard over this account's distributions on purpose: the exact ARN
      # would create a cycle (key policy -> distribution -> bucket -> this key
      # via the bucket's encryption configuration). The bucket policy, which
      # has no such cycle, pins the exact distribution ARN.
      {
        Sid       = "AllowCloudFrontOriginDecrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = {
          StringLike = {
            "AWS:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"
          }
        }
      },
      # The write path: the platform PUTs objects and S3 calls GenerateDataKey
      # on the writer's behalf. Rather than naming the platform role here, use
      # of the key is confined to S3-mediated requests from this account.
      {
        Sid       = "AllowS3WritePathInAccount"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
            "kms:ViaService"    = "s3.${var.region}.amazonaws.com"
          }
        }
      },
    ]
  })

  tags = {
    Name        = "${var.default_name}-crl"
    Description = var.default_description
  }
}

resource "aws_cloudfront_origin_access_control" "crl" {
  count = local.crl_cloudfront_count

  name                              = local.crl_fqdn
  description                       = "Sole reader of the private CRL bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_acm_certificate" "crl" {
  count    = local.crl_cloudfront_count
  provider = aws.use1

  domain_name       = local.crl_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "${var.default_name}-crl"
    Description = var.default_description
  }
}

resource "aws_route53_record" "crl_acm_validation" {
  for_each = merge([
    for cert in aws_acm_certificate.crl : {
      for dvo in cert.domain_validation_options : dvo.domain_name => {
        name  = dvo.resource_record_name
        type  = dvo.resource_record_type
        value = dvo.resource_record_value
      }
    }
  ]...)

  zone_id         = aws_route53_zone.cluster.id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.value]
  allow_overwrite = true
}

# Blocks until ACM sees the validation records resolve. If the zone has not been
# delegated from its parent yet, this is where the apply waits and eventually
# times out.
resource "aws_acm_certificate_validation" "crl" {
  count    = local.crl_cloudfront_count
  provider = aws.use1

  certificate_arn         = aws_acm_certificate.crl[0].arn
  validation_record_fqdns = [for r in aws_route53_record.crl_acm_validation : r.fqdn]
}

# AWS-managed cache policy, looked up by name rather than by its well-known id.
# CRLs carry their own freshness (nextUpdate), so optimized caching is the right
# default; the header of s3.tf records the staleness trade.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  count = local.crl_cloudfront_count
  name  = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "crl" {
  count = local.crl_cloudfront_count

  enabled = true
  comment = "${local.crl_fqdn} - CRL distribution over a private origin"
  aliases = [local.crl_fqdn]

  # v4-only on purpose: the S3 website endpoint in public-bucket mode is
  # v4-only, and the two modes should resolve the same way. PriceClass_100
  # keeps cost down; widen it if validators are spread worldwide.
  is_ipv6_enabled = false
  price_class     = "PriceClass_100"

  origin {
    origin_id = "s3-crl"
    # The REST endpoint, not the website endpoint: OAC signs SigV4 against the
    # S3 API, which website endpoints do not speak.
    domain_name              = aws_s3_bucket.veto_crls.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.crl[0].id
  }

  default_cache_behavior {
    target_origin_id = "s3-crl"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    # allow-all, never redirect-to-https: validators speak plain HTTP, and a
    # 301 to HTTPS is a fetch failure to a CRL client, not a hint.
    viewer_protocol_policy = "allow-all"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized[0].id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # The validation waiter's ARN, not the certificate's own: CloudFront
    # rejects an unvalidated certificate at create time, and this reference is
    # what serializes distribution creation behind validation.
    acm_certificate_arn      = aws_acm_certificate_validation.crl[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = {
    Name        = "${var.default_name}-crl"
    Description = var.default_description
  }
}

# Applied after the distribution exists, so the grant can name its exact ARN.
resource "aws_s3_bucket_policy" "veto_crls_cloudfront" {
  count  = local.crl_cloudfront_count
  bucket = aws_s3_bucket.veto_crls.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOriginRead"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.veto_crls.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.crl[0].arn
          }
        }
      },
    ]
  })
}
