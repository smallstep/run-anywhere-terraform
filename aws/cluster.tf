#----------------------------------------------------------------------------------
# 
# This file is where we set up an EKS Cluster for Kubernetes and related resources
# 
#----------------------------------------------------------------------------------

# Set an authentication endpoint for the Kubernetes provider in kubernetes.tf
data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.eks.name
}

locals {
  public_cidrs = concat(data.aws_subnet.public[*].cidr_block)
}

# Set up the SG assigned to each cluster with a base set of recommended ICMP rules
# If you want to test from the public internet, you can uncomment the `public_facing` line
# Defaults to only allowing these rules internal to the VPC
module "eks_base_security_group_rules" {
  source            = "./base_security_group_rules"
  # public_facing     = true
  security_group_id = aws_security_group.eks.id
}

resource "aws_eks_cluster" "eks" {
  name     = local.default_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    endpoint_public_access  = true
    endpoint_private_access = false
    security_group_ids      = [aws_security_group.eks.id]
    subnet_ids              = local.subnets_private
  }

  tags = {
    Name        = local.default_name
    Description = local.default_description
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_1,
    aws_iam_role_policy_attachment.eks_cluster_2,
  ]
}

# Node pool to run the Replicated stack
resource "aws_eks_node_group" "eks" {
  cluster_name    = aws_eks_cluster.eks.name
  instance_types  = local.k8s_configs.instance_types
  node_group_name = local.default_name
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = local.subnets_private

  scaling_config {
    desired_size = local.k8s_configs.pool_desired
    max_size     = local.k8s_configs.pool_max
    min_size     = local.k8s_configs.pool_min
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name        = local.default_name
    Description = local.default_description
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_1,
    aws_iam_role_policy_attachment.eks_node_group_2,
    aws_iam_role_policy_attachment.eks_node_group_3,
  ]
}

resource "aws_iam_role" "eks_cluster" {
  name = "${local.default_name}-eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role" "eks_node_group" {
  name = "${local.default_name}-eks-node-group"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_1" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# Enable Security Groups for Pods
# Reference: https://docs.aws.amazon.com/eks/latest/userguide/security-groups-for-pods.html
resource "aws_iam_role_policy_attachment" "eks_cluster_2" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.eks_cluster.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_1" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_2" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_3" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

# Security Group for the cluster and its nodes
resource "aws_security_group" "eks" {
  name        = "${local.default_name}-eks"
  vpc_id      = data.aws_subnet.public[0].vpc_id
  description = local.default_description

  tags = {
    Name        = "${local.default_name}-eks"
    Description = local.default_description
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Allow connections from the load balancer in the public subnets
resource "aws_security_group_rule" "incoming_connections" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = local.public_cidrs
  security_group_id = aws_security_group.eks.id
  description       = "Allow connections from the NLB stood up in the public subnets"
}

# Allow ingress from the DB instances
resource "aws_security_group_rule" "rds_to_eks" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  security_group_id        = aws_security_group.eks.id
  description              = "Allow ingress from the PostgreSQL DBs running in the smallstep project"

  lifecycle {
    create_before_destroy = true
  }
}

# Allow ingress from our Redis instance
resource "aws_security_group_rule" "redis_to_eks" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.redis.id
  security_group_id        = aws_security_group.eks.id
  description              = "Allow ingress from the Redis instance running in the smallstep projet"

  lifecycle {
    create_before_destroy = true
  }
}

# Required to enable public load balancing
resource "null_resource" "allow_public_lb" {
  for_each = toset(local.subnets_public)
  provisioner "local-exec" {
    command = "aws ec2 create-tags --resources ${each.key} --tags Key=kubernetes.io/role/elb,Value=1"
  }
}

# EKS will only be able to bind properly to the selected subnets if each includes the following tag.
# Using a null resource since they aren't managed by this terraform project.
resource "null_resource" "tag_subnets" {
  for_each = toset(local.subnets_private)
  provisioner "local-exec" {
    command = "aws ec2 create-tags --resources ${each.key} --tags Key=kubernetes.io/cluster/${aws_eks_cluster.eks.name},Value=shared"
  }
}

# OIDC Provider

data "tls_certificate" "eks" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "eks_policy" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:smallstep:landlord"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    principals {
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
      type        = "Federated"
    }
  }
}

resource "aws_iam_role" "eks" {
  assume_role_policy = data.aws_iam_policy_document.eks_policy.json
  name               = "eks"
}

resource "aws_iam_role_policy" "ca_kms" {
  name = "${local.default_name}-ca-kms"
  role = aws_iam_role.eks.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["kms:GetPublicKey", "kms:TagResource", "kms:CreateAlias", "kms:CreateKey", "kms:Sign"]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}
