# Stage 2 of 2: everything Kubernetes, consuming stage 1 via remote state.
# Separate roots because the kubernetes/helm providers below are configured
# from the EKS cluster stage 1 creates — a provider cannot be configured from
# a resource in its own apply. Credentials come from an exec plugin that
# re-runs `aws eks get-token` whenever the cached token expires — a static
# aws_eks_cluster_auth token lives ~15 minutes, and this apply's long waits
# (10m per helm release, 15m for the bootstrap Job) can outlive it, failing
# mid-apply with Unauthorized. Nothing long-lived lands on disk or in state,
# and the plugin uses the same ambient AWS credentials as the aws provider.

data "terraform_remote_state" "platform" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = var.platform_state_key
    region = var.state_region
  }
}

locals {
  # Everything this root needs about the platform comes from its outputs,
  # including the deployment name: duplicating it as a variable here only
  # created a value an operator could set differently from the one platform
  # was applied with, and nothing would have said so.
  p = data.terraform_remote_state.platform.outputs
}

provider "aws" {
  region = local.p.region

  default_tags {
    tags = {
      deployment = local.p.name
      managed-by = "terraform"
      tf-root    = "workloads"
    }
  }
}

# Same exec plugin twice, two syntaxes: exec is a block on the v2 kubernetes
# provider and an attribute on the v3 helm provider — a bare exec {} block
# inside helm's kubernetes map fails validation.
provider "kubernetes" {
  host                   = local.p.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(local.p.eks_cluster_ca_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.p.eks_cluster_name, "--region", local.p.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.p.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(local.p.eks_cluster_ca_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.p.eks_cluster_name, "--region", local.p.region]
    }
  }
}

module "cluster_addons" {
  source = "../modules/cluster-addons"

  name                        = local.p.name
  region                      = local.p.region
  cluster_name                = local.p.eks_cluster_name
  vpc_id                      = local.p.vpc_id
  kms_key_arn                 = local.p.platform_kms_key_arn
  lb_controller_role_arn      = local.p.lb_controller_role_arn
  lb_controller_chart_version = var.lb_controller_chart_version
  fluent_bit_role_arn         = local.p.fluent_bit_role_arn
  fluent_bit_chart_version    = var.fluent_bit_chart_version
  container_log_group_name    = local.p.container_log_group_name
}

module "smallstep_bootstrap" {
  source = "../modules/smallstep-bootstrap"

  name               = local.p.name
  region             = local.p.region
  namespace          = local.p.namespace
  bootstrap_role_arn = local.p.bootstrap_role_arn
  rds_host           = local.p.rds_host
  rds_port           = local.p.rds_port
  app_secret_arns    = local.p.app_secret_arns
}
