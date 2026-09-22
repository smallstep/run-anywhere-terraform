# Terraform >= 1.11 is a hard floor, not a preference: S3-native state locking
# (use_lockfile), write-only arguments, and ephemeral resources are all
# load-bearing in this root (see modules/data for the password pattern).

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 7.0"
    }
    random = {
      source = "hashicorp/random"
      # 3.7 introduced ephemeral resource support; modules/data's ephemeral
      # random_password needs it, so the floor matches that module's.
      version = ">= 3.7"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      deployment = var.name
      managed-by = "terraform"
      tf-root    = "platform"
    }
  }
}

# CloudFront requires its ACM certificate in us-east-1 regardless of where the
# distribution's origin lives. Only modules/crl-bucket (crl_mode=cloudfront)
# uses this alias.
provider "aws" {
  alias  = "use1"
  region = "us-east-1"

  default_tags {
    tags = {
      deployment = var.name
      managed-by = "terraform"
      tf-root    = "platform"
    }
  }
}
