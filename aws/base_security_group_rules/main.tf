#----------------------------------------------------------------------------------
#
# This module creates some basic rules that should be present in every SG.
#
#----------------------------------------------------------------------------------
#
#  If set to public-facing, we will allow ICMP traffic from everywhere.
#  If not, we will only allow ICMP from the CIDR block of our VPC
#
#----------------------------------------------------------------------------------


# To prevent possible mis-match between selected subnet and its VPC,
# we just use this data source to pull that data.
data "aws_vpc" "selected" {
  id = var.vpc
}

locals {
  cidr_blocks = concat(var.security_groups_cidr_blocks, [data.aws_vpc.selected.cidr_block])
}

# Allow all egress traffic
resource "aws_security_group_rule" "egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = local.cidr_blocks
  security_group_id = var.security_group_id
  description       = "Allow egress to internal VPC."

  lifecycle {
    create_before_destroy = true
  }
}

# Allow useful/necessary ICMP traffic (www.shouldiblockicmp.com)
# Echo Reply/Ping
resource "aws_security_group_rule" "ingress1" {
  type              = "ingress"
  from_port         = 0 # ICMP Type
  to_port           = 0 # ICMP Code
  protocol          = "icmp"
  cidr_blocks       = local.cidr_blocks
  security_group_id = var.security_group_id
  description       = "Base ICMP rule - managed by Terraform."

  lifecycle {
    create_before_destroy = true
  }
}

# Fragmentation Required
resource "aws_security_group_rule" "ingress2" {
  type              = "ingress"
  from_port         = 3 # ICMP Type
  to_port           = 4 # ICMP Code
  protocol          = "icmp"
  cidr_blocks       = local.cidr_blocks
  security_group_id = var.security_group_id
  description       = "Base ICMP rule - managed by Terraform."

  lifecycle {
    create_before_destroy = true
  }
}

# Echo Request/Ping
resource "aws_security_group_rule" "ingress3" {
  type              = "ingress"
  from_port         = 8 # ICMP Type
  to_port           = 0 # ICMP Code
  protocol          = "icmp"
  cidr_blocks       = local.cidr_blocks
  security_group_id = var.security_group_id
  description       = "Base ICMP rule - managed by Terraform."

  lifecycle {
    create_before_destroy = true
  }
}

# Time Exceeded
resource "aws_security_group_rule" "ingress4" {
  type              = "ingress"
  from_port         = 11 # ICMP Type
  to_port           = 0  # ICMP Code
  protocol          = "icmp"
  cidr_blocks       = local.cidr_blocks
  security_group_id = var.security_group_id
  description       = "Base ICMP rule - managed by Terraform."

  lifecycle {
    create_before_destroy = true
  }
}
