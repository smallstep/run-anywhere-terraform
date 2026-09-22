# The CRL distribution point. Two modes: the product's expected public
# bucket, or a private bucket behind CloudFront for environments that permit
# no public buckets and require customer-managed keys everywhere.
#
# How the platform uses this bucket is fixed by the platform, not this module.
# The CRL distributor (veto) writes revocation lists to s3://crl.<domain> —
# the bucket NAME is derived by the KOTS app from the base domain, it is not a
# config knob — and every certificate validator on every device fetches
# http://crl.<domain>/<file> anonymously, because that URL is stamped into the
# CRL Distribution Points extension of every certificate the platform issues.
# Plain HTTP is intrinsic to CRL distribution, not sloppiness: a validator
# cannot be required to establish TLS in order to check revocation of the very
# certificate that TLS would depend on. Every public CA distributes CRLs over
# HTTP for the same reason.
#
# A private bucket with SSE-KMS default encryption 403s every anonymous fetch
# twice over — once at the bucket (no public policy) and once at KMS
# (anonymous principals hold no kms:Decrypt) — so every CRL download fails and
# revocation silently never happens. Each mode below is therefore a complete,
# internally consistent shape, selected by one variable.
#
# public-bucket mode is the product's expected shape: S3 static website
# hosting, a genuinely public bucket policy, SSE-S3. It is also the ONE
# deliberate public bucket in the deployment — the state bucket and everything else
# keep Block Public Access on.
#
# cloudfront mode is the no-public-buckets posture: the bucket stays private
# (BPA fully on), objects are SSE-KMS under a dedicated CMK, and a CloudFront
# distribution with Origin Access Control is the only reader. The costs are
# real and worth stating: a distribution + a us-east-1 ACM certificate + a
# second CMK, and — the operational one — edge caching means a freshly
# published CRL can take up to the cache TTL to appear at every edge, where
# public-bucket mode serves it immediately. Within CRL semantics that is
# tolerable (validators trust a CRL until its nextUpdate anyway); when it
# isn't, the manual fix is `aws cloudfront create-invalidation --paths '/*'`.

locals {
  fqdn = "crl.${var.domain}"

  public_count     = var.crl_mode == "public-bucket" ? 1 : 0
  cloudfront_count = var.crl_mode == "cloudfront" ? 1 : 0
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# --- The bucket (both modes) -------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket = local.fqdn

  # CRLs are derived data — the platform regenerates them on its next cycle —
  # so the evaluation posture lets a destroy empty the bucket.
  force_destroy = !var.deletion_protection
}

# ACLs disabled entirely. Public read (when granted at all) comes from the
# bucket policy, never from object ACLs — so a writer can never accidentally
# widen or narrow access per-object.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# --- public-bucket mode ------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "public" {
  count  = local.public_count
  bucket = aws_s3_bucket.this.id

  # All four off, on this bucket only: the one deliberate public bucket in the
  # deployment. Note this is the BUCKET-level block — if the ACCOUNT-level S3 Block
  # Public Access is ever enabled in this account, the policy below is rejected
  # no matter what we set here, and nothing in this module can fix it.
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "public" {
  count  = local.public_count
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      # SSE-S3, never SSE-KMS: decrypting a KMS-encrypted object requires
      # kms:Decrypt on the key, and an anonymous principal has no permissions
      # at all — SSE-KMS here 403s every CRL fetch (see the header).
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "public" {
  count  = local.public_count
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AnonymousCRLRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.this.arn}/*"
      },
    ]
  })

  # S3 rejects a public PutBucketPolicy while BlockPublicPolicy is still on,
  # and Terraform has no implicit ordering between these two resources — the
  # dependency must be spelled out or fresh applies fail intermittently.
  depends_on = [aws_s3_bucket_public_access_block.public]
}

resource "aws_s3_bucket_website_configuration" "public" {
  count  = local.public_count
  bucket = aws_s3_bucket.this.id

  # The website endpoint is what serves plain HTTP (the REST endpoint is
  # HTTPS-biased and path-styled). Website hosting routes virtual-hosted: S3
  # picks the bucket whose NAME equals the Host header, which is the real
  # reason the bucket must literally be named crl.<domain>. index.html is
  # required by the API; nothing ever fetches it.
  index_document {
    suffix = "index.html"
  }
}

resource "aws_route53_record" "public" {
  count   = local.public_count
  zone_id = var.zone_id
  name    = local.fqdn
  type    = "A"

  alias {
    # Route 53 special-cases aliases to S3 websites: the target is the
    # REGIONAL website domain (s3-website.<region>.amazonaws.com) paired with
    # the region's S3 hosted zone id — not the bucket-specific endpoint.
    # Virtual-hosted routing (Host header == bucket name) does the rest.
    # website_domain + hosted_zone_id is the provider-documented pair.
    name                   = aws_s3_bucket_website_configuration.public[0].website_domain
    zone_id                = aws_s3_bucket.this.hosted_zone_id
    evaluate_target_health = false
  }
}

# --- cloudfront mode ---------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "cloudfront" {
  count  = local.cloudfront_count
  bucket = aws_s3_bucket.this.id

  # Fully locked. The CloudFront service-principal policy below is not
  # "public" in BPA's evaluation (it carries a SourceArn condition), so it
  # coexists with all four blocks on.
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# A dedicated key rather than var.kms_key_arn: granting cloudfront.amazonaws.com
# on the shared platform key would mean this module reaching into modules/kms's
# key policy — cross-module coupling that turns every key-policy edit into a
# two-module change. A per-purpose key keeps the CloudFront grant, and its
# consequences, contained here.
resource "aws_kms_key" "crl" {
  count = local.cloudfront_count

  description             = "${local.fqdn} CRL objects (CloudFront origin)"
  enable_key_rotation     = true
  deletion_window_in_days = var.deletion_protection ? 30 : 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Standard root delegation; without it the key is unmanageable the
        # moment the applying role changes.
        Sid       = "EnableIAMDelegation"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        # CloudFront must decrypt origin objects to serve them. The SourceArn
        # is a WILDCARD over this account's distributions on purpose: the
        # exact distribution ARN would create a cycle (key policy needs the
        # distribution, distribution needs the bucket, bucket's SSE config
        # needs this key). The bucket policy — a separate resource with no
        # such cycle — pins the exact ARN, so precision lives there.
        # StringLike, not StringEquals: StringEquals does not expand '*'.
        Sid       = "AllowCloudFrontOriginDecrypt"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = {
          StringLike = {
            "AWS:SourceArn" = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/*"
          }
        }
      },
      {
        # The write path: veto PUTs objects and S3 calls GenerateDataKey on
        # the writer's behalf. This module does not know which role veto runs
        # as (and iam-app does not know this key exists), so instead of naming
        # a principal, confine use to S3-mediated requests from this account.
        Sid       = "AllowS3WritePathInAccount"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource  = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
            "kms:ViaService"    = "s3.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      },
    ]
  })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfront" {
  count  = local.cloudfront_count
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.crl[0].arn
    }
  }
}

resource "aws_cloudfront_origin_access_control" "this" {
  count = local.cloudfront_count

  name                              = local.fqdn
  description                       = "Sole reader of the private CRL bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# The certificate lives in us-east-1 (aws.use1) because CloudFront accepts no
# other region — see versions.tf.
resource "aws_acm_certificate" "crl" {
  count    = local.cloudfront_count
  provider = aws.use1

  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  # The conditional keeps the [0] index unevaluated in public-bucket mode.
  # Keys (domain names) are known at plan; only the record values wait on ACM.
  for_each = var.crl_mode == "cloudfront" ? {
    for dvo in aws_acm_certificate.crl[0].domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  } : {}

  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.value]
  allow_overwrite = true
}

# Blocks until ACM sees the validation records resolve. If the zone has not
# been NS-delegated from the parent yet, this waiter is where the apply hangs
# and eventually times out — same failure mode as SES identity verification
# in modules/ses-smtp.
resource "aws_acm_certificate_validation" "crl" {
  count    = local.cloudfront_count
  provider = aws.use1

  certificate_arn         = aws_acm_certificate.crl[0].arn
  validation_record_fqdns = [for r in aws_route53_record.acm_validation : r.fqdn]
}

# AWS-managed cache policy; its well-known id is
# 658327ea-f89d-4fab-a63d-7e88639e58f6, looked up by name so the constant is
# not hardcoded. CRLs carry their own freshness (nextUpdate), so optimized
# caching is the right default — the header records the staleness trade.
data "aws_cloudfront_cache_policy" "caching_optimized" {
  count = local.cloudfront_count
  name  = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "this" {
  count = local.cloudfront_count

  enabled = true
  comment = "${local.fqdn} — CRL distribution over a private origin"
  aliases = [local.fqdn]

  # v4-only on purpose: the S3 website endpoint in public-bucket mode is
  # v4-only, and publishing AAAA in one mode but not the other would make the
  # two modes resolve differently. PriceClass_100 keeps cost down; widen it
  # if validators are spread worldwide rather than near your devices.
  is_ipv6_enabled = false
  price_class     = "PriceClass_100"

  origin {
    origin_id = "s3-crl"
    # The REST endpoint, not the website endpoint: OAC signs SigV4 against the
    # S3 API, which website endpoints do not speak. That is also why the two
    # modes cannot share their Route 53 alias target.
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this[0].id
  }

  default_cache_behavior {
    target_origin_id = "s3-crl"
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    # allow-all, never redirect-to-https: validators speak plain HTTP (see the
    # header — the CDP URL in every issued certificate is http://), and a 301
    # to HTTPS is a fetch failure to a CRL client, not a hint.
    viewer_protocol_policy = "allow-all"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized[0].id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # Referencing the validation waiter's certificate_arn (not the cert's own)
    # is what serializes distribution creation behind a validated cert —
    # CloudFront rejects an unvalidated ACM certificate at create time.
    acm_certificate_arn      = aws_acm_certificate_validation.crl[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Separate resource, applied after the distribution exists — which is what
# dissolves the chicken-and-egg the KMS key policy had to wildcard around:
# here the exact distribution ARN is available, so the grant is precise.
resource "aws_s3_bucket_policy" "cloudfront" {
  count  = local.cloudfront_count
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontOriginRead"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.this.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this[0].arn
          }
        }
      },
    ]
  })
}

resource "aws_route53_record" "cloudfront" {
  count   = local.cloudfront_count
  zone_id = var.zone_id
  name    = local.fqdn
  type    = "A"

  alias {
    name = aws_cloudfront_distribution.this[0].domain_name
    # Every CloudFront distribution lives in the same global hosted zone,
    # Z2FDTNDATAQYW2 — a documented Route 53 AliasTarget constant. The
    # distribution exports it as hosted_zone_id, so reference that rather
    # than restating the magic string.
    zone_id                = aws_cloudfront_distribution.this[0].hosted_zone_id
    evaluate_target_health = false
  }
}
