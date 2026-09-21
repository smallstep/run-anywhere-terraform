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

    # Every platform service account in the namespace assumes this role: the
    # release annotates landlord, gateway, veto, mission-control and others
    # with the same role ARN, so pinning a single account name here breaks
    # everything but that one.
    condition {
      test     = "StringLike"
      variable = "${replace(aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.k8s_namespace}:*"]
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
module "eks_base_security_group_rules" {
  source                      = "./base_security_group_rules"
  vpc                         = var.vpc
  security_group_id           = aws_eks_cluster.eks.vpc_config[0].cluster_security_group_id
  security_groups_cidr_blocks = var.security_groups_cidr_blocks
}

resource "aws_eks_cluster" "eks" {
  name     = var.default_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.eks_version

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.smallstep.arn
    }
  }

  enabled_cluster_log_types = ["api", "authenticator", "audit", "scheduler", "controllerManager"]

  # We need access to configure the EKS cluster from the workstation. Ignoring these tfsec rules. The
  # Security Groups limit access via CIDR and we set public_access_cidrs to allow access to the CIDR list in
  # var.security_groups_cidr_blocks
  #tfsec:ignore:aws-eks-no-public-cluster-access tfsec:ignore:aws-eks-no-public-cluster-access-to-cidr
  vpc_config {
    endpoint_public_access  = !var.cluster_endpoint_private_only
    endpoint_private_access = true
    public_access_cidrs     = var.cluster_endpoint_private_only ? [] : var.security_groups_cidr_blocks
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

# Worker node launch template: encrypted root volumes and IMDSv2. Without a
# launch template the node group gets default-sized, unencrypted roots and
# IMDSv1; a hop limit of 2 keeps IMDS reachable from pods (the load balancer
# controller discovers its region and VPC through it).
resource "aws_launch_template" "eks" {
  name_prefix = "${var.default_name}-eks-"

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = var.node_root_volume_size
      volume_type           = "gp3"
      encrypted             = true
      kms_key_id            = aws_kms_key.smallstep.arn
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = var.default_name
      Description = var.default_description
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Node pool to run the Replicated stack
resource "aws_eks_node_group" "eks" {
  cluster_name    = aws_eks_cluster.eks.name
  instance_types  = var.k8s_instance_types
  node_group_name = var.default_name
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = var.subnets_private

  launch_template {
    id      = aws_launch_template.eks.id
    version = aws_launch_template.eks.latest_version
  }

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
      # kms:CreateKey cannot be resource-scoped: there is no key, hence no ARN,
      # until the call succeeds. The CA service creates its signing keys at
      # runtime and tags and aliases them in the same breath.
      {
        Sid      = "CreateCAKeys"
        Action   = ["kms:CreateKey", "kms:TagResource", "kms:CreateAlias"]
        Effect   = "Allow"
        Resource = "*"
      },
      # Sign with keys whose ARNs are unknowable at plan time (created above).
      {
        Sid      = "SignWithRuntimeKeys"
        Action   = ["kms:Sign", "kms:Verify", "kms:GetPublicKey", "kms:DescribeKey"]
        Effect   = "Allow"
        Resource = "*"
      },
      # The Terraform-managed gateway JWT signing key, named explicitly so the
      # statement above can later be narrowed to runtime-created keys.
      {
        Sid      = "SignGatewayJWT"
        Action   = ["kms:Sign", "kms:GetPublicKey", "kms:DescribeKey"]
        Effect   = "Allow"
        Resource = aws_kms_key.gateway_jwt.arn
      },
      # CRL publishing. Object actions only match "<bucket>/*"; bucket actions
      # only match the bucket ARN.
      {
        Sid      = "PublishCRLs"
        Action   = ["s3:PutObject", "s3:DeleteObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Effect   = "Allow"
        Resource = [aws_s3_bucket.veto_crls.arn, "${aws_s3_bucket.veto_crls.arn}/*"]
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

# New requirement to run the EBS CSI Driver
# which is a new requirement to mount persistent volumes
resource "aws_iam_role_policy_attachment" "eks_node_group_4" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
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

# We must manually add the EBS CSI addon to allow
# persistent volumes to attach
resource "null_resource" "ebs_csi" {
  provisioner "local-exec" {
    command = "aws eks create-addon --cluster-name ${aws_eks_cluster.eks.name} --addon-name aws-ebs-csi-driver"
  }

  depends_on = [
    aws_eks_cluster.eks,
    aws_eks_node_group.eks
  ]
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
