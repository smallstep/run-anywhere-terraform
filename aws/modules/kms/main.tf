# Two keys, two very different jobs.
#
# aws_kms_key.platform is the single customer-managed symmetric key behind
# everything at rest in the deployment: RDS, ElastiCache, Secrets Manager, the EKS
# secrets envelope, EBS volumes on the node group, and the CloudWatch
# container log group. One key rather than one-per-service: encryption keys
# under the customer's control, governed by one explicit, auditable policy —
# not key sprawl. The key policy is therefore written out statement by
# statement instead of leaning on the permissive AWS default, so it can be
# read top to bottom.
#
# aws_kms_key.gateway_jwt is an asymmetric ECC P-256 sign/verify key. The
# platform's gateway signs session JWTs with it and never sees the private
# key; the KOTS config carries only the key reference (see the
# gateway_jwt_signing_key output, whose awskms:key-id=<uuid> form goes into
# the config verbatim) plus the base64 public key for verification. It keeps
# the AWS default key policy (account root kms:*) on purpose: only the shared
# app role uses it, through IAM (modules/iam-app statement 3), and an
# asymmetric key cannot use ViaService-style scoping anyway.
#
# What is deliberately NOT here: landlord (the platform CA) creates MORE
# asymmetric sign/verify keys at RUNTIME via kms:CreateKey using the shared
# app role — one per CA it operates. Those keys are intentionally not
# Terraform-managed (Terraform cannot know about keys the application mints),
# which means `terraform destroy` will not remove them. They must be swept at
# teardown or they linger, pending deletion windows and all (`make
# destroy-all` prints a reminder).

data "aws_caller_identity" "current" {}

# .name rather than .region: the v6 provider prefers .region, but .region does
# not exist at the 5.95 floor this module supports. The v6 deprecation warning
# is the accepted cost of spanning both majors.
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# --- Platform key (symmetric, everything at rest) ----------------------------

data "aws_iam_policy_document" "platform" {
  # Account-root full access is not a courtesy — it is what makes IAM policies
  # on this key work at all. KMS evaluates key policy and IAM policy together
  # ONLY when the key policy delegates to the account; remove this statement
  # and every IAM-granted use of the key (EKS envelope encryption, the app
  # role, your own admin credentials) silently stops, and with no principal
  # left who can edit the policy the key is unrecoverable short of an AWS
  # support case. That is the classic KMS lockout, and it is why this
  # statement survives an otherwise least-privilege policy.
  statement {
    sid       = "AccountRootDelegation"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  # Key use for the AWS services that encrypt on our behalf. Principal "*"
  # looks alarming but is fenced twice: kms:CallerAccount pins it to this
  # account, and kms:ViaService means the request must arrive through one of
  # the four named services in this region — a caller with stolen credentials
  # cannot kms:Decrypt directly, only ask Secrets Manager/RDS/ElastiCache/EBS
  # to do so under their own resource-level authorization.
  statement {
    sid = "ServiceUseViaService"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }

    # ec2.<region> is how EBS volume encryption presents itself to KMS; there
    # is no ebs.<region> service principal for ViaService.
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.${local.region}.amazonaws.com",
        "rds.${local.region}.amazonaws.com",
        "elasticache.${local.region}.amazonaws.com",
        "ec2.${local.region}.amazonaws.com",
      ]
    }
  }

  # CreateGrant carries the kms:GrantIsForAWSResource condition, and that
  # condition key exists ONLY in grant-operation request contexts — folding it
  # into the statement above would make its Bool test fail for every
  # Encrypt/Decrypt call (missing context key) and break Secrets Manager. So
  # grants get their own statement: RDS, ElastiCache, and EBS all take a grant
  # at attach time and then operate under it, and the condition guarantees the
  # grantee is an AWS service resource, never an arbitrary principal.
  statement {
    sid       = "ServiceGrantsViaService"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "secretsmanager.${local.region}.amazonaws.com",
        "rds.${local.region}.amazonaws.com",
        "elasticache.${local.region}.amazonaws.com",
        "ec2.${local.region}.amazonaws.com",
      ]
    }

    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }

  # CloudWatch Logs is a service principal, not a ViaService pass-through, so
  # it needs its own statement. This one guards a specific failure mode: the
  # eks module creates log group /<name>/eks/containers encrypted with
  # this key, and WITHOUT this statement that creation fails —
  # "AccessDeniedException: The specified KMS key does not exist or is not
  # allowed to be used" — which reads like a missing key, not a missing policy
  # statement. The EncryptionContext condition confines the grant to this
  # deployment's log-group namespace instead of every log group in the account.
  statement {
    sid = "CloudWatchLogsEncryption"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/${var.name}/*"]
    }
  }

  # No statement for EKS: the cluster's secrets-envelope encryption
  # authorizes through the cluster IAM role, which the AccountRootDelegation
  # statement already delegates to IAM. Adding a ViaService entry for EKS
  # here would be dead policy.
}

resource "aws_kms_key" "platform" {
  description         = "${var.name} platform data-at-rest (RDS, ElastiCache, Secrets Manager, EKS secrets, EBS, CloudWatch Logs)"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.platform.json

  # 7 is the AWS minimum, for the evaluation posture: a deployment that is
  # torn down and rebuilt cannot re-create the alias while a 30-day corpse
  # holds it.
  deletion_window_in_days = var.deletion_protection ? 30 : 7

  tags = { Name = "${var.name}-platform" }
}

resource "aws_kms_alias" "platform" {
  name          = "alias/${var.name}-platform"
  target_key_id = aws_kms_key.platform.key_id
}

# --- Gateway JWT signing key (asymmetric P-256) ------------------------------

resource "aws_kms_key" "gateway_jwt" {
  description              = "${var.name} gateway JWT signing (ES256; private key never leaves KMS)"
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = var.deletion_protection ? 30 : 7

  # No policy argument: the AWS default (account root kms:*) is deliberate —
  # see the header. No enable_key_rotation either: KMS cannot rotate
  # asymmetric key material, and setting it is an API error.

  tags = { Name = "${var.name}-gateway-jwt" }
}

resource "aws_kms_alias" "gateway_jwt" {
  name          = "alias/${var.name}-gateway-jwt"
  target_key_id = aws_kms_key.gateway_jwt.key_id
}

# The KOTS config wants the verifying half as base64(PEM); fetching it here
# means the public key rides the same terraform-output contract as everything
# else instead of a hand-run `aws kms get-public-key`.
data "aws_kms_public_key" "gateway_jwt" {
  key_id = aws_kms_key.gateway_jwt.arn
}
