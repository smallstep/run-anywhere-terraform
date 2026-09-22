# Module-local provider window, deliberately identical to the roots'. A module
# whose floor quietly drifts above its callers' is how a working root stops
# initializing months later; keeping one window (>= 5.95, < 7.0) everywhere
# means init resolves a single provider build for the whole graph.
#
# The floor is the roots' floor — the 5.95 line is where the write-only
# argument surface modules/data depends on settled; this module does not use
# it but agrees on the number rather than inventing a second one. The ceiling
# excludes the next provider major before it exists: the wrapped
# terraform-aws-modules releases get their v6/v7 compatibility on their own
# schedule, and a floating ceiling would volunteer this deployment as the test.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 7.0"
    }
  }
}
