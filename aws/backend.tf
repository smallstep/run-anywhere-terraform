#----------------------------------------------------------------------------------
# 
# This file funtions as the source of all Terraform providers, data, and versioning
# utilized for the AWS Onprem Terraform Project.
# 
#----------------------------------------------------------------------------------


# ------------------------------- Providers ----------------------------------------
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.0"
    }

    http = {
      source  = "hashicorp/http"
      version = ">= 2.1"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.6"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.1"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
  }
}

provider "aws" {
  region = var.region
}

provider "kubernetes" {
  host                   = aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)

  # Since EKS uses a token with a 15 minute lifetime. Use this exec to keep it up to date.
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.eks.name]
    command     = "aws"
  }
}

# ------------------------------- Project Data ----------------------------------------

# Data sources used universally through project
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_region" "current" {}

data "aws_subnet" "public" {
  count = length(var.subnets_public)
  id    = var.subnets_public[count.index]
}