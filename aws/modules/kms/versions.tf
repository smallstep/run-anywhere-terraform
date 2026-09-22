# The floor is 5.95 (write-only arguments elsewhere in this root); the
# ceiling excludes the next major on principle. The range spans provider v5
# and v6, which is why main.tf reads data.aws_region.current.name instead of
# the v6-only .region.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 7.0"
    }
  }
}
