# Public zone and platform hostnames.
#
# One public Route 53 zone for the base domain, NS-delegated from the parent
# zone (delegation is a manual step in the parent zone's account, and until
# it lands nothing below resolves). The zone is deliberately public even for
# a private deployment: public DNS is load-bearing for Let's Encrypt HTTP-01,
# which is how the platform gets its TLS certificates at install time. A
# private zone would boot a cluster that can never finish issuing its own
# certs.
#
# Every platform hostname is an A record answering with ALL of the lobby EIPs
# — the addresses modules/network pre-allocated for the KOTS app's NLB. That
# is what lets this module run in the same apply as the network, before the
# app or its load balancer exist: the addresses are fixed even though the NLB
# is not. Multi-value A answers give round-robin across AZs; TTL 300 keeps a
# bad answer short-lived during install/reinstall cycles.
#
# Two names that look like they belong here are intentionally absent:
#
#   - "crl": owned by modules/crl-bucket. It aliases S3 website hosting (or
#     CloudFront in crl_mode=cloudfront), not the NLB — pointing it at the
#     lobby EIPs would serve 404s for every CRL fetch.
#   - "control.infra": mission-control gets its OWN NLB, created by KOTS at
#     install time, whose address cannot be known here. A post-install step
#     reconciles that record into this zone (a CNAME to the NLB hostname).
#
# The record list is complete on purpose. att and approvalq.infra in
# particular are easy to leave out, and their absence surfaces as attestation
# and approval-queue timeouts long after an apparently clean install.

locals {
  # Everything the lobby NLB fronts. "gateway.api" and friends are dotted
  # subdomains of the base domain, not separate zones.
  lobby_hostnames = toset([
    "app",
    "api",
    "auth",
    "att",
    "gateway.api",
    "gateway",
    "inventory",
    "ocsp",
    "scim.api",
    "scif.infra",
    "approvalq.infra",
    "river.infra",
    "tunnel",
    "linkedca.api",
  ])
}

resource "aws_route53_zone" "this" {
  name = var.domain

  # Route 53 will happily delete a zone with only its SOA/NS records left, but
  # a stray manual record (reconcile-dns.sh writes one) blocks destroy. That
  # is the desired failure: it forces an operator to look before the zone —
  # and the delegation pointing at it — silently disappears.
}

resource "aws_route53_record" "lobby" {
  for_each = local.lobby_hostnames

  zone_id = aws_route53_zone.this.zone_id
  name    = "${each.value}.${var.domain}"
  type    = "A"
  ttl     = 300
  records = var.lobby_eip_public_ips
}

# Per-authority CA hostnames are minted at runtime as
# <authority>.<team-slug>.ca.<domain> — the set is unknowable at plan time, so
# a wildcard under "ca" covers all of them. Broader than "*.<team-slug>.ca"
# on purpose: the slug is application configuration, and folding it in here would make a
# slug change a DNS change too.
resource "aws_route53_record" "wildcard_ca" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "*.ca.${var.domain}"
  type    = "A"
  ttl     = 300
  records = var.lobby_eip_public_ips
}
