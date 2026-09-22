# Two provider configurations, because CloudFront will only attach an ACM
# certificate that lives in us-east-1 — regardless of where the distribution's
# origin (or anything else in the deployment) lives. The root passes both providers
# unconditionally (providers = { aws = aws, aws.use1 = aws.use1 }): provider
# wiring in Terraform is static, so the alias must be declared and satisfied
# even when crl_mode=public-bucket never touches it.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 5.95, < 7.0"
      configuration_aliases = [aws.use1]
    }
  }
}
