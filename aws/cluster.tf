#----------------------------------------------------------------------------------
# 
# This file is where we set up an EKS Cluster for Kubernetes and related resources
# 
#----------------------------------------------------------------------------------

# Set an authentication endpoint for the Kubernetes provider in kubernetes.tf
data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.eks.name
}

data "aws_iam_policy_document" "eks_service_account" {
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

data "tls_certificate" "eks" {
  url = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

locals {
  public_cidrs = concat(data.aws_subnet.public[*].cidr_block)
}

# Set up the SG assigned to each cluster with a base set of recommended ICMP rules
# If you want to test from the public internet, you can uncomment the `public_facing` line
# Defaults to only allowing these rules internal to the VPC
module "eks_base_security_group_rules" {
  source            = "./base_security_group_rules"
  # The SG is created with this rule already applied
  egress_all        = false
  public_facing     = var.security_groups_public
  security_group_id = aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
}

resource "aws_eks_cluster" "eks" {
  name     = var.default_name
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    endpoint_public_access  = true
    endpoint_private_access = false
    subnet_ids              = var.subnets_private
  }

  tags = {
    Name        = var.default_name
    Description = var.default_description
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
  instance_types  = var.k8s_instance_types
  node_group_name = var.default_name
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = var.subnets_private

  scaling_config {
    desired_size = var.k8s_pool_desired
    max_size     = var.k8s_pool_max
    min_size     = var.k8s_pool_min
  }

  update_config {
    max_unavailable = 1
  }

  tags = {
    Name        = var.default_name
    Description = var.default_description
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.eks_node_group_1,
    aws_iam_role_policy_attachment.eks_node_group_2,
    aws_iam_role_policy_attachment.eks_node_group_3,
  ]
}

resource "aws_iam_openid_connect_provider" "eks" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}

resource "aws_iam_role" "eks_cluster" {
  name = "${var.default_name}-eks-cluster"

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
  name = "${var.default_name}-eks-node-group"

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

resource "aws_iam_role" "eks_service_account" {
  name_prefix        = "${var.default_name}-service-account"
  assume_role_policy = data.aws_iam_policy_document.eks_service_account.json
}

resource "aws_iam_role_policy" "eks_service_account" {
  name = "${var.default_name}-ca-kms"
  role = aws_iam_role.eks_service_account.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["kms:GetPublicKey", "kms:TagResource", "kms:CreateAlias", "kms:CreateKey", "kms:Sign"]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action   = ["s3:PutObject"]
        Effect   = "Allow"
        Resource = aws_s3_bucket.veto_crls.arn
      },
    ]
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

# Allow connections from the load balancer in the public subnets
resource "aws_security_group_rule" "incoming_connections" {
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = local.public_cidrs
  security_group_id = aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
  description       = "Allow connections from the NLB stood up in the public subnets"
}

# Allow ingress from the DB instances
resource "aws_security_group_rule" "rds_to_eks" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.rds.id
  security_group_id        = aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
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
  security_group_id        = aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
  description              = "Allow ingress from the Redis instance running in the smallstep projet"

  lifecycle {
    create_before_destroy = true
  }
}

# Required to enable public load balancing
resource "null_resource" "allow_public_lb" {
  for_each = toset(var.subnets_public)
  provisioner "local-exec" {
    command = "aws ec2 create-tags --resources ${each.key} --tags Key=kubernetes.io/role/elb,Value=1"
  }
}

# Pull down the kube config file after the cluster's been fulling created
resource "null_resource" "kube_config" {
  provisioner "local-exec" {
    command = "aws eks --region ${var.region} update-kubeconfig --name ${aws_eks_cluster.eks.name}"
  }

  depends_on = [
    aws_eks_cluster.eks,
    aws_eks_node_group.eks
  ]
}

# EKS sets up a SG with a tag tying ownership back to the EKS cluster.
# This tag bricks Target Groups and prevents them from registering targets.
resource "null_resource" "remove_eks_sg_tag" {
  provisioner "local-exec" {
    command = "aws ec2 delete-tags --resources ${aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id} --tags Key=kubernetes.io/cluster/${aws_eks_cluster.eks.name},Value=owned"
  }

  depends_on = [
    aws_eks_cluster.eks,
    aws_eks_node_group.eks
  ]
}

# EKS will only be able to bind properly to the selected subnets if each includes the following tag.
# Using a null resource since they aren't managed by this terraform project.
resource "null_resource" "tag_private_subnets" {
  for_each = toset(var.subnets_private)
  provisioner "local-exec" {
    command = "aws ec2 create-tags --resources ${each.key} --tags Key=kubernetes.io/cluster/${aws_eks_cluster.eks.name},Value=shared"
  }
}