# Matches the root pins: the module uses aws_eip.domain and expects the
# aws_region data source to still export `name`, both true across this range.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 7.0"
    }
  }
}
