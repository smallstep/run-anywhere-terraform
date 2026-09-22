# The VPC — created here, or brought by the caller.
#
# create_vpc = true is a thin wrapper over terraform-aws-modules/vpc. Wrapping
# rather than reimplementing keeps the surface to review small and keeps
# route-table/NAT/endpoint details in well-trodden code.
#
# create_vpc = false takes an existing VPC and its subnets. The module then
# owns exactly two things on them: the subnet role tags the load balancer
# controller discovers placement by (as aws_ec2_tag resources, so nothing else
# about the subnets is touched), and the lobby EIPs. Routing, NAT and
# endpoints are the caller's; the private subnets need a route to the
# internet for image pulls.
#
# Shape either way: public subnets carry the internet-facing NLBs and the NAT
# gateway; everything that holds a key or a certificate record — EKS nodes,
# RDS, ElastiCache — sits in private subnets with no inbound path.
#
# The lobby EIPs are the one piece of load-balancer state Terraform owns. The
# KOTS app creates the lobby Service itself (type LoadBalancer), and the AWS
# Load Balancer Controller materializes the NLB at install time — after this
# root has applied. Left to its own devices the controller would pick fresh
# public IPs, which means DNS could not be created until after the app exists
# and every NLB recreation would strand the zone. Pre-allocating the EIPs here
# and passing their allocation IDs through the KOTS config (the Service's
# service.beta.kubernetes.io/aws-load-balancer-eip-allocations annotation)
# breaks that cycle: modules/dns can answer with these IPs in the same apply,
# and the addresses survive any later NLB replacement. The controller REQUIRES
# exactly one EIP per public subnet the NLB spans. A count mismatch does not
# fail the Terraform apply; it surfaces later as the controller refusing to
# provision the NLB, so the EIP count follows the public subnet count here.

locals {
  name   = var.name
  create = var.create_vpc

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /20 private subnets first, then /20 public. Deriving both from the VPC CIDR
  # means one CIDR variable covers both.
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + var.az_count)]

  vpc_id             = local.create ? module.vpc[0].vpc_id : var.vpc_id
  public_subnet_ids  = local.create ? module.vpc[0].public_subnets : var.public_subnet_ids
  private_subnet_ids = local.create ? module.vpc[0].private_subnets : var.private_subnet_ids

  # One lobby EIP per public subnet, whoever created the subnets.
  eip_count = local.create ? var.az_count : length(var.public_subnet_ids)
}

# The root does not pass a region; the provider's region is authoritative.
# `name` (not `region`) because the `region` attribute does not exist at the
# aws 5.95 floor this module pins — `.region` would hard-fail the plan there,
# while `.name` merely warns on 6.x.
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  # Local Zones and Wavelength zones cannot host RDS or NLB-with-EIP subnets,
  # and silently produce an unschedulable deployment if they sneak into the
  # list.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

module "vpc" {
  count = local.create ? 1 : 0

  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway = true

  # One NAT gateway for the whole VPC keeps cost down. Production should run
  # one per AZ, so a single-AZ failure cannot take egress with it.
  single_nat_gateway = var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tags the AWS Load Balancer Controller uses to discover where to place
  # internet-facing vs internal load balancers. Without them the lobby Service
  # sits in Pending forever with a subnet-discovery error buried in the
  # controller's logs.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# S3 gateway endpoint. Free, and it keeps ECR image-layer pulls and CRL writes
# off the NAT gateway — cheaper, and one less hop in the data path. The VPC
# module stopped managing endpoints in v5, so this is declared directly. Only
# the private route tables need it: nothing in the public subnets originates
# S3 traffic. Not created for a caller-provided VPC, whose route tables this
# module does not own.
resource "aws_vpc_endpoint" "s3" {
  count = local.create ? 1 : 0

  vpc_id            = module.vpc[0].vpc_id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc[0].private_route_table_ids

  tags = { Name = "${local.name}-vpce-s3" }
}

# The same role tags on caller-provided subnets, owned one tag at a time so a
# destroy removes only these and a plan never fights the caller over the rest.
resource "aws_ec2_tag" "public_elb_role" {
  for_each = local.create ? toset([]) : toset(var.public_subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "private_elb_role" {
  for_each = local.create ? toset([]) : toset(var.private_subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

# The lobby NLB's static addresses — see the header for why these exist before
# the load balancer does. Indexed by count so the allocation-ID list stays
# ordered and stable; removing an AZ from the middle would reshuffle the tail,
# which is exactly the kind of change that should be loud in a plan.
resource "aws_eip" "lobby" {
  count = local.eip_count

  domain = "vpc"

  tags = { Name = "${local.name}-lobby-${count.index}" }
}
