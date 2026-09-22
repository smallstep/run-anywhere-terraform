# Outbound email for the platform. The only mail it sends is team invitations
# (courier relays them through whatever single SMTP endpoint the KOTS config
# names), so this module's job is small: produce one host/port/username and one
# Secrets Manager secret holding {username, password}, in exactly the same
# shape whether the mail is real or not.
#
# ses mode is real mail. Two SES facts dominate the shape:
#
#   1. SES SMTP AUTH only accepts credentials derived from an IAM user's
#      access key — there is no role/IRSA path to the SMTP interface. Hence
#      the one IAM user in the deployment, which would otherwise be an anachronism.
#      The provider computes the SMTP password client-side from the secret key
#      (SigV4 derivation, keyed to the provider's region), which means both
#      the raw access-key secret and the derived password sit in Terraform
#      state. That is a documented exception, same as the redis auth_token in
#      modules/data: the state bucket is the trust boundary here.
#
#   2. A fresh account is in the SES SANDBOX: it may send only TO verified
#      addresses (and identities) until AWS grants production access, which is
#      a support-case away and not automatable here. Invitation-email tests
#      therefore use a verified recipient address until then. Unverified
#      recipients fail at the SMTP transaction (554), visible in courier's
#      logs; that is the sandbox, not a platform fault.
#
# Domain identity verification rides on Easy DKIM: SES hands back three tokens
# and looks for the matching _domainkey CNAMEs in public DNS. Until the
# zone is NS-delegated from the parent those records resolve nowhere and the
# identity stays "verification pending" — SES retries for 72 hours, so a late
# delegation self-heals without a re-apply.
#
# dummy mode exists so the platform can be stood up before (or without) any of
# the above: same secret, same outputs, host smtp.invalid and a throwaway
# password. The platform boots normally; courier logs a delivery failure per
# invitation. That is acceptable and expected — nothing else in the platform
# depends on mail actually arriving.

locals {
  ses_count   = var.smtp_mode == "ses" ? 1 : 0
  dummy_count = var.smtp_mode == "ses" ? 0 : 1

  # The SES SMTP endpoint is per-region, and the SigV4-derived password is
  # region-specific too — host and credentials must agree, so both key off
  # the provider region.
  smtp_host     = var.smtp_mode == "ses" ? "email-smtp.${data.aws_region.current.name}.amazonaws.com" : "smtp.invalid"
  smtp_username = var.smtp_mode == "ses" ? aws_iam_access_key.smtp[0].id : "dummy"
  smtp_password = var.smtp_mode == "ses" ? aws_iam_access_key.smtp[0].ses_smtp_password_v4 : random_password.dummy[0].result
}

# .name, not the newer .region: the aws provider constraint spans 5.x and 6.x,
# and .region does not exist before 6.0 while .name survives (deprecated)
# through 6.x. .name is the only spelling valid across the whole range.
data "aws_region" "current" {}

# --- ses mode ----------------------------------------------------------------

# A DOMAIN identity, not an address identity: verifying the domain lets the
# platform send as any mailbox at it, and Easy DKIM (the default) is what
# produces the tokens consumed below.
resource "aws_sesv2_email_identity" "domain" {
  count = local.ses_count

  email_identity = var.domain
}

resource "aws_route53_record" "dkim" {
  # Easy DKIM is always exactly three tokens, so the count is a constant —
  # which keeps the plan stable even though the token values themselves are
  # unknown until the identity exists.
  count = local.ses_count * 3

  zone_id = var.zone_id
  name    = "${aws_sesv2_email_identity.domain[0].dkim_signing_attributes[0].tokens[count.index]}._domainkey.${var.domain}"
  type    = "CNAME"
  ttl     = 600
  records = ["${aws_sesv2_email_identity.domain[0].dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

# The one IAM user in the deployment — see the header for why no role can do this.
resource "aws_iam_user" "smtp" {
  count = local.ses_count

  name = "${var.name}-ses-smtp"
}

resource "aws_iam_user_policy" "send" {
  count = local.ses_count

  name = "ses-send"
  user = aws_iam_user.smtp[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Resource * because the account contains no SES identities other
        # than the deployment's own domain; scoping to the identity ARN would buy
        # nothing and break the day someone sends from a subdomain address.
        Sid      = "Send"
        Effect   = "Allow"
        Action   = ["ses:SendRawEmail", "ses:SendEmail"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_access_key" "smtp" {
  count = local.ses_count

  user = aws_iam_user.smtp[0].name

  # ses_smtp_password_v4 on this resource IS the SMTP password — no API call
  # returns it; the provider derives it locally from the secret key for the
  # provider's region. Both values live in state (documented exception,
  # header above).
}

# --- dummy mode --------------------------------------------------------------

# Nothing ever authenticates with this. It exists so the secret has the same
# {username, password} shape in both modes and no consumer needs a mode switch.
resource "random_password" "dummy" {
  count = local.dummy_count

  length  = 24
  special = false
}

# --- The secret (both modes) -------------------------------------------------

resource "aws_secretsmanager_secret" "smtp" {
  name       = "${var.name}/app/smtp"
  kms_key_id = var.kms_key_arn

  # In the evaluation posture a secret lingering in scheduled-deletion would
  # block the next apply with a name collision, and the contents are
  # re-derivable from the resources above anyway.
  recovery_window_in_days = var.deletion_protection ? 7 : 0
}

resource "aws_secretsmanager_secret_version" "smtp" {
  secret_id = aws_secretsmanager_secret.smtp.id
  secret_string = jsonencode({
    username = local.smtp_username
    password = local.smtp_password
  })
}
