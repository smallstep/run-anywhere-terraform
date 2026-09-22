# Matches the root pins. Route 53 resources here predate both bounds; the
# range exists so this module can never drag the root somewhere it isn't.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 7.0"
    }
  }
}
