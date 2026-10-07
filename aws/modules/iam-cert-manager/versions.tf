# Same provider range as every module in this root: floor 5.95 for the
# write-only arguments used elsewhere, ceiling short of the next major.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 7.0"
    }
  }
}
