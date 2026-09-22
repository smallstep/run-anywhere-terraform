# Floors here are load-bearing, not aspirational, because this module is
# where the write-only password pattern lives: password_wo on aws_db_instance
# and secret_string_wo on aws_secretsmanager_secret_version need aws >= 5.95,
# and the ephemeral random_password feeding them needs random >= 3.7 — the
# release that introduced ephemeral resource support; 3.6 cannot run this
# module.
#
# The < 7.0 ceiling matches the root: provider 7.x is allowed to break
# argument shapes (6.0 removed several), and a deployment that must apply cleanly on
# a fresh checkout cannot float across a major. Terraform >= 1.11 is inherited
# from the root's versions.tf — ephemeral resources and write-only arguments
# are language features, not provider ones.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7"
    }
  }
}
