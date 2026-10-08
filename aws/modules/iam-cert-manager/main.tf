# cert-manager's DNS-01 role. The SCEP service answers on
# <team-slug>.scep.<base_domain>, one hostname per team minted at runtime, so
# its certificate is the wildcard *.scep.<base_domain> — and Let's Encrypt
# issues a wildcard only through a DNS-01 challenge, which means cert-manager
# has to write TXT records into the zone. The KOTS config carries this role's
# ARN (https_settings.acme_dns01_aws_role_arn); the app puts it on
# cert-manager's service account as eks.amazonaws.com/role-arn and starts the
# controller with --issuer-ambient-credentials so a namespaced Issuer may use
# it.
#
# Unlike modules/iam-app, the trust policy names ONE service account. The
# shared app role wildcards the namespace because the chart annotates a dozen
# SAs with it; Route 53 write access is held by exactly one pod, and widening
# the shared role instead would hand every platform service the zone.
#
# The policy is cert-manager's documented Route 53 policy, tightened where AWS
# allows it: GetChange cannot be scoped (change IDs are minted per request),
# record changes are limited to this zone and to TXT records via the
# ChangeResourceRecordSetsRecordTypes condition, and ListHostedZonesByName is
# what lets the KOTS config leave the zone ID empty and have cert-manager find
# the zone by name. The generated config passes the zone ID; the statement
# stays so the role also works for an operator who does not.

locals {
  oidc_issuer = split(":oidc-provider/", var.oidc_provider_arn)[1]
}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "IRSATrust"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
    }
  }
}

resource "aws_iam_role" "cert_manager" {
  name               = "${var.name}-cert-manager"
  description        = "IRSA role for cert-manager's ACME DNS-01 solver against the ${var.name} Route 53 zone (KOTS acme_dns01_aws_role_arn)"
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = { Name = "${var.name}-cert-manager" }
}

data "aws_iam_policy_document" "dns01" {
  statement {
    sid       = "ReadChangeStatus"
    actions   = ["route53:GetChange"]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    sid = "ChangeZoneRecords"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
    ]
    resources = ["arn:aws:route53:::hostedzone/${var.zone_id}"]

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "route53:ChangeResourceRecordSetsRecordTypes"
      values   = ["TXT"]
    }
  }

  statement {
    sid       = "FindZoneByName"
    actions   = ["route53:ListHostedZonesByName"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "dns01" {
  name   = "${var.name}-cert-manager-dns01"
  role   = aws_iam_role.cert_manager.id
  policy = data.aws_iam_policy_document.dns01.json
}
