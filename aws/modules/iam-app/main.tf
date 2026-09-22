# The shared application role — the value of the KOTS config's
# key_management_settings.aws_cluster_iam_role. The chart annotates roughly
# thirteen platform service accounts with this one role
# (eks.amazonaws.com/role-arn), so it is a single IRSA role trusted by the
# whole namespace rather than one role per service. Wildcarding the
# service-account name in the trust policy is therefore deliberate: the app
# decides which SAs get the annotation, and enumerating them here would mean
# chasing chart releases forever. Enumerating them IS the hardening option
# for a production posture, and is noted as such below — the wildcard is the
# trade, made in the open.
#
# The inline policy has four statements, each with a comment on why it is
# shaped the way it is. The pattern common to the first two: landlord (the
# platform CA) creates its CA signing keys at RUNTIME via kms:CreateKey, so
# their ARNs do not exist at plan time and cannot be resource-scoped — a fact
# about the AWS API, not a policy choice. The runtime keys also do not die
# with `terraform destroy`; schedule their deletion by hand after teardown
# (`make destroy-all` prints a reminder).
#
# Known failure modes this policy's shape prevents: scoping kms:CreateKey to
# a key ARN makes landlord's first CA creation fail with AccessDenied;
# granting s3:PutObject on the bucket ARN instead of the object ARN pattern
# makes every CRL publish fail with AccessDenied while the policy looks
# superficially correct.

locals {
  # The trust-policy condition keys are named after the OIDC issuer host/path
  # (no scheme), which is exactly the ARN's suffix after ":oidc-provider/".
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

    # Any service account in the app namespace may assume the role — see the
    # header for why. Hardening: replace the wildcard with the enumerated SA
    # list once the installed chart version pins it.
    condition {
      test     = "StringLike"
      variable = "${local.oidc_issuer}:sub"
      values   = ["system:serviceaccount:${var.namespace}:*"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.name}-smallstep-app"
  description        = "Shared IRSA role for all ${var.name} platform service accounts (KOTS aws_cluster_iam_role)"
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = { Name = "${var.name}-smallstep-app" }
}

data "aws_iam_policy_document" "app" {
  # (1) kms:CreateKey CANNOT be resource-scoped — before the call succeeds
  # there is no key, so there is no ARN for IAM to match; the action is only
  # valid against Resource "*". That is an AWS API fact: scoped to a key ARN,
  # this statement can never authorize anything, and landlord's first attempt
  # to mint a CA key dies with AccessDenied. TagResource and CreateAlias ride
  # along because landlord tags and aliases each key it creates in the same
  # breath.
  statement {
    sid = "LandlordCreateCAKeys"
    actions = [
      "kms:CreateKey",
      "kms:TagResource",
      "kms:CreateAlias",
    ]
    resources = ["*"]
  }

  # (2) Sign/verify against keys whose ARNs are unknowable at plan time —
  # landlord created them at runtime (statement 1), so "*" is the only
  # resource that can name them. The future hardening is tag-based ABAC:
  # landlord tags its keys, and an aws:ResourceTag condition here would
  # confine this statement to exactly those keys without enumerating ARNs.
  statement {
    sid = "SignWithRuntimeKeys"
    actions = [
      "kms:Sign",
      "kms:GetPublicKey",
      "kms:DescribeKey",
      "kms:Verify",
    ]
    resources = ["*"]
  }

  # (3) The same sign/read actions again, pinned explicitly to the
  # Terraform-managed gateway JWT key. Redundant today — statement 2's "*"
  # covers it — but it means statement 2 can later be tag-scoped to
  # landlord's runtime keys without silently breaking the gateway, whose key
  # is created here by Terraform and would not carry landlord's tags.
  statement {
    sid = "SignGatewayJWT"
    actions = [
      "kms:Sign",
      "kms:GetPublicKey",
      "kms:DescribeKey",
    ]
    resources = [var.gateway_jwt_key_arn]
  }

  # (4) CRL publishing. Put/Delete are OBJECT actions and only ever match the
  # /* resource — granted on the bare bucket ARN alone, s3:PutObject matches
  # nothing, and every CRL upload fails AccessDenied under a policy that
  # reads as correct. List/GetBucketLocation are BUCKET actions and only
  # match the bucket ARN; IAM's action-to-resource matching keeps the two
  # halves of this statement from bleeding into each other.
  statement {
    sid = "PublishCRLs"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      var.crl_bucket_arn,
      "${var.crl_bucket_arn}/*",
    ]
  }
}

# Inline rather than a managed policy: this policy has exactly one legitimate
# principal, and inlining makes it impossible to attach elsewhere by accident.
resource "aws_iam_role_policy" "app" {
  name   = "${var.name}-smallstep-app"
  role   = aws_iam_role.app.id
  policy = data.aws_iam_policy_document.app.json
}
