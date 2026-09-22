#------------------------------------------------------------------------------------
# 
# This file is where we set up all resources used for routing DNS to the application
# 
#------------------------------------------------------------------------------------

# The k8s cluster will bind to two IP addresses which will then route to Route53
# These addresses cannot change at any point so we instantiate an EIP
resource "aws_eip" "cluster" {
  count = length(var.subnets_public)
  tags = {
    Name        = var.default_name
    Description = var.default_description
  }
}

# Set up a hosted zone in Route53 and subsequent records routing to the above IP
resource "aws_route53_zone" "cluster" {
  name    = var.base_domain
  comment = "Hosted zone routing traffic to the smallstep cluster"

  tags = {
    Name        = var.default_name
    Description = var.default_description
  }
}

resource "aws_route53_record" "landlord_teams" {
  zone_id = aws_route53_zone.cluster.id
  name    = "*.ca.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "magpie_teams" {
  zone_id = aws_route53_zone.cluster.id
  name    = "*.logs.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "tunnel" {
  zone_id = aws_route53_zone.cluster.id
  name    = "tunnel.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "web_api" {
  zone_id = aws_route53_zone.cluster.id
  name    = "api.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "web_api_gateway" {
  zone_id = aws_route53_zone.cluster.id
  name    = "gateway.api.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "web_api_scim" {
  zone_id = aws_route53_zone.cluster.id
  name    = "scim.api.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "web_app" {
  zone_id = aws_route53_zone.cluster.id
  name    = "app.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "web_auth" {
  zone_id = aws_route53_zone.cluster.id
  name    = "auth.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "ocsp" {
  zone_id = aws_route53_zone.cluster.id
  name    = "ocsp.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

# An alias, not a CNAME to the S3 REST endpoint: the REST endpoint does not
# serve anonymous plain-HTTP GETs by hostname. The target follows crl_mode — the
# bucket's website endpoint (whose virtual-hosted routing is why the bucket is
# named crl.<base_domain>) or the CloudFront distribution. See s3.tf.
resource "aws_route53_record" "crl" {
  zone_id = aws_route53_zone.cluster.id
  name    = "crl.${aws_route53_zone.cluster.name}"
  type    = "A"

  alias {
    name                   = local.crl_cloudfront ? one(aws_cloudfront_distribution.crl[*].domain_name) : one(aws_s3_bucket_website_configuration.veto_crls[*].website_domain)
    zone_id                = local.crl_cloudfront ? one(aws_cloudfront_distribution.crl[*].hosted_zone_id) : aws_s3_bucket.veto_crls.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "scif" {
  zone_id = aws_route53_zone.cluster.id
  name    = "scif.infra.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "linkedca_api" {
  zone_id = aws_route53_zone.cluster.id
  name    = "linkedca.api.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

# The attestation CA (guardian). Agents enrolling by attestation reach it here.
resource "aws_route53_record" "att" {
  zone_id = aws_route53_zone.cluster.id
  name    = "att.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

# The REST/GraphQL API. gateway.api is the web application's API ingress;
# API clients, the Terraform provider and the agent use this name.
resource "aws_route53_record" "gateway" {
  zone_id = aws_route53_zone.cluster.id
  name    = "gateway.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "approvalq" {
  zone_id = aws_route53_zone.cluster.id
  name    = "approvalq.infra.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "river" {
  zone_id = aws_route53_zone.cluster.id
  name    = "river.infra.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}

resource "aws_route53_record" "inventory" {
  zone_id = aws_route53_zone.cluster.id
  name    = "inventory.${aws_route53_zone.cluster.name}"
  ttl     = 300
  type    = "A"
  records = concat(aws_eip.cluster[*].public_ip)
}