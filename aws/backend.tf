#----------------------------------------------------------------------------------
# 
# This file funtions as the source of all Terraform providers, data, and versioning
# utilized for the AWS Onprem Terraform Project.
# 
#----------------------------------------------------------------------------------


# ------------------------------- Providers ----------------------------------------
terraform {
  # State for this project will be stored in a dedicated S3 bucket
  backend "s3" {
    encrypt        = true
    bucket         = "smallstep-terraform-state"
    key            = "smallstep/terraform.tfstate"
    region         = "us-west-1"
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.6"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.1"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }

  required_version = ">=1.0.2"
}

provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.eks.certificate_authority[0].data)
  config_path            = local.k8s_configs.kube_config_path

  # Since EKS uses a token with a 15 minute lifetime. Use this exec to keep it up to date.
  exec {
    api_version = "client.authentication.k8s.io/v1alpha1"
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
  count = length(local.subnets_public)
  id = local.subnets_public[count.index]
}

# ---------------------------------- Variables ----------------------------------------

# -------------------------------------------------------------------------------------
#                                !!! IMPORTANT !!!  
# -------------------------------------------------------------------------------------
# When running first apply set: terraform apply -var smtp_password="<value>" \
#                                               -var private_issuer_password="<value>" 
#                                               
#                                               (if you set `hsm_enabled = true`) \
#                                               -var hsm_pin="<value"
# -------------------------------------------------------------------------------------
# Subsequent applies will not require you to set these variables, as changes
# will be ignored.
# -------------------------------------------------------------------------------------

variable "private_issuer_password" {
  description = "The private issuer password used by the create_secrets.sh script."
  default     = ""
  type        = string
  sensitive   = true
}

variable "smtp_password" {
  description = "The SMTP password used by the create_secrets.sh script."
  default     = ""
  type        = string
  sensitive   = true
}

variable "hsm_pin" {
  description = "The PIN used for your HSMs, only used when setting up with HSM support"
  default     = ""
  type        = string
  sensitive   = true
}