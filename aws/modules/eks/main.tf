# The EKS cluster and every IAM identity that trusts its OIDC provider.
#
# This wraps terraform-aws-modules/eks ~> 20.31 rather than hand-rolling the
# two dozen resources a functioning cluster actually is. Two settings deserve
# a note:
#
#   - cluster_version is PINNED through a variable instead of floating. The
#     KOTS bundle ships cert-manager v1.5.5, old enough that a Kubernetes
#     minor bump can retire an API surface it still speaks. The variable is the
#     escape hatch: if an upgrade breaks the bundled cert-manager, the fix is a
#     one-line pin, not an emergency.
#
#   - The endpoint posture is a toggle. cluster_endpoint_private_only=true is
#     the prod answer — the API server reachable only in-VPC, kubectl and the
#     kots CLI both needing a bastion or VPN to function. The default
#     keeps the public endpoint with api_public_access_cidrs pinned to
#     operator ranges. Node-to-API traffic rides the private endpoint either
#     way.
#
# The four IRSA roles live here rather than in a separate IAM root because
# their trust policies are functions of this cluster's OIDC provider ARN;
# splitting them out would only add a remote-state hop to express the same
# dependency. (The app's shared role is different — it lives in modules/iam-app
# because its lifecycle follows the app, not the cluster.)
#
# Failure modes this file records:
#   - EBS CSI without its own IRSA role does not error; it falls back to the
#     node instance role and PVCs sit Pending while the addon hangs CREATING
#     until Terraform gives up (see the addon block).
#   - disk_size on a managed node group is silently ignored whenever the
#     module builds a launch template — which it does by default.
#     block_device_mappings is the shape that actually lands on the instances
#     (see the node group).
#   - create_kms_key defaults to true; left alone, the module mints its own
#     CMK for secrets encryption and quietly ignores the platform key (see
#     cluster_encryption_config).

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  region     = data.aws_region.current.name
  account_id = data.aws_caller_identity.current.account_id
}

# --- Container log group -----------------------------------------------------

# Created here (not by fluent-bit's auto_create_group) so retention and CMK
# encryption are terraform-owned facts rather than whatever the daemonset felt
# like. The name is load-bearing: modules/kms scopes its logs-service key
# statement to /<name>/*, so moving this group out from under that prefix
# fails CreateLogGroup with an opaque KMS AccessDenied that reads like a
# permissions bug in the wrong service.
resource "aws_cloudwatch_log_group" "containers" {
  count = var.enable_logging ? 1 : 0

  name              = "/${var.name}/eks/containers"
  retention_in_days = 30
  kms_key_id        = var.kms_key_arn
}

# --- IRSA: EBS CSI driver ----------------------------------------------------

# Scoped to the one service account that needs it rather than granted to every
# pod on the node via the instance profile — the same least-privilege shape
# every role in this file follows.
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name             = "${var.name}-ebs-csi"
  attach_ebs_csi_policy = true

  # The node roots below are cut with the platform CMK, and dynamically
  # provisioned PVCs will be too; without grant/decrypt on that key the CSI
  # controller leaves volumes stuck in "waiting for a volume to be created".
  ebs_csi_kms_cmk_ids = [var.kms_key_arn]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# --- IRSA: AWS Load Balancer Controller --------------------------------------

# The KOTS app's NLB annotations are inert until this controller exists;
# workloads installs the chart and must run its service account under the
# exact name pinned in this trust policy.
module "lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name                              = "${var.name}-lb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

# --- IRSA: fluent-bit (gated) ------------------------------------------------

# Write-only, and only to the one log group above — a log shipper needs no
# read path. CreateLogGroup is included so the shipper survives the group
# being recreated out from under it, but it is scoped to this exact group.
data "aws_iam_policy_document" "fluent_bit" {
  count = var.enable_logging ? 1 : 0

  statement {
    sid = "ShipContainerLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    # The group ARN plus ":*" for the streams beneath it; the provider strips
    # the API's trailing ":*" from the arn attribute, so both forms are needed.
    resources = [
      aws_cloudwatch_log_group.containers[0].arn,
      "${aws_cloudwatch_log_group.containers[0].arn}:*",
    ]
  }
}

resource "aws_iam_policy" "fluent_bit" {
  count = var.enable_logging ? 1 : 0

  name   = "${var.name}-fluent-bit"
  policy = data.aws_iam_policy_document.fluent_bit[0].json
}

# The aws-for-fluent-bit chart names its service account after the Helm
# release (the fullname helper) unless serviceAccount.name is set. This trust
# policy pins kube-system:fluent-bit, so modules/cluster-addons must set that
# name explicitly — leave the chart default and the pods fail
# sts:AssumeRoleWithWebIdentity on an OIDC subject mismatch.
module "fluent_bit_irsa" {
  count = var.enable_logging ? 1 : 0

  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name = "${var.name}-fluent-bit"

  role_policy_arns = {
    logs = aws_iam_policy.fluent_bit[0].arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:fluent-bit"]
    }
  }
}

# --- IRSA: bootstrap job -----------------------------------------------------

# The workloads bootstrap job reads the app secrets out of Secrets Manager
# to seed databases and render KOTS config. It gets exactly that: read the
# secrets under one prefix, decrypt the CMK only when Secrets Manager is the
# caller. It cannot use the key directly, and it cannot read anything outside
# the prefix.
data "aws_iam_policy_document" "bootstrap" {
  statement {
    sid     = "ReadAppSecrets"
    actions = ["secretsmanager:GetSecretValue"]
    # Secrets Manager appends a random 6-character suffix to every secret's
    # ARN (…/master-Ab12Cd); the trailing * exists to cover it. Drop it and
    # GetSecretValue fails AccessDenied while every name looks correct.
    resources = [
      "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:${var.app_secrets_prefix}/*",
    ]
  }

  statement {
    sid       = "DecryptViaSecretsManager"
    actions   = ["kms:Decrypt"]
    resources = [var.kms_key_arn]

    # ViaService means the role can decrypt only through Secrets Manager —
    # handed the raw ciphertext, it can do nothing with it.
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "bootstrap" {
  name   = "${var.name}-bootstrap"
  policy = data.aws_iam_policy_document.bootstrap.json
}

module "bootstrap_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.44"

  role_name = "${var.name}-bootstrap"

  role_policy_arns = {
    secrets = aws_iam_policy.bootstrap.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.namespace}:smallstep-bootstrap"]
    }
  }
}

# --- Cluster -----------------------------------------------------------------

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.name
  cluster_version = var.cluster_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # IRSA is how every role above gets assumed — per service account, never via
  # node instance-profile credentials that every pod would inherit.
  enable_irsa = true

  # The prod-posture toggle (see the header). The private endpoint is always
  # on so flipping the public one off strands no nodes, only operators.
  cluster_endpoint_public_access       = !var.cluster_endpoint_private_only
  cluster_endpoint_public_access_cidrs = var.api_public_access_cidrs
  cluster_endpoint_private_access      = true

  # v20 access entries: the applying principal gets cluster-admin, so the
  # first kubectl works without an aws-auth ConfigMap ritual. Anyone else
  # needs their own access entry — being able to apply this Terraform is not
  # the same as being able to read the cluster.
  enable_cluster_creator_admin_permissions = true

  # Control-plane audit into CloudWatch. api/audit/authenticator is the
  # SIEM-relevant subset; controllerManager and scheduler add volume, not
  # signal.
  cluster_enabled_log_types = ["api", "audit", "authenticator"]

  # Envelope-encrypt Kubernetes secrets with the platform CMK. create_kms_key
  # must be false or the module mints its own key and silently ignores this
  # one — the cluster comes up green and encrypted, just not with the key the
  # audit trail says.
  create_kms_key = false
  cluster_encryption_config = {
    provider_key_arn = var.kms_key_arn
    resources        = ["secrets"]
  }

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
    # The service account role is not optional. Without it the controller
    # falls back to the node instance role, which has no EC2 permissions, and
    # the pods crash-loop on a dry-run DescribeAvailabilityZones while the
    # addon sits in CREATING until Terraform times out after 20 minutes. The
    # failure reads like a cluster problem and is really a missing IAM role.
    aws-ebs-csi-driver = {
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # The module's default node SG only opens ephemeral ports (1025-65535)
  # between nodes. With the VPC CNI, pod IPs live on node ENIs behind this SG,
  # so cross-node pod-to-pod traffic to privileged container ports is DROPPED:
  # the lobby on one node proxying to ingress-nginx-internal on another over
  # 80/443 hangs, while everything same-node works, which makes it look like a
  # listener problem. Kubernetes assumes a flat pod network; give it one.
  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "node-to-node (pod-to-pod under the VPC CNI), all ports"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }

  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]

      min_size     = var.node_min
      max_size     = var.node_max
      desired_size = var.node_desired

      # AL2 AMIs end with Kubernetes 1.32; pinning AL2023 now means the
      # cluster_version escape hatch never collides with an AMI-family
      # migration at the worst possible moment.
      ami_type = "AL2023_x86_64_STANDARD"

      # IMDSv2 enforced. Hop limit 2, not 1: pods sit one network hop behind
      # the instance, and the ip-target NLBs this app fronts itself with do
      # not change that — drop to 1 and IRSA-less pods lose IMDS entirely.
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "required"
        http_put_response_hop_limit = 2
      }

      # Not disk_size — that attribute is ignored whenever the module builds a
      # launch template, which is its default (recorded in the header). 100
      # GiB because KOTS, the admin console, and the app's images share the
      # root; default-sized roots end in disk-pressure evictions that present
      # as random pod churn. Encryption with the platform CMK requires the key
      # policy to admit the AutoScaling service-linked role, or the ASG
      # launches nothing and says so only in its scaling-activity log.
      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 100
            volume_type           = "gp3"
            encrypted             = true
            kms_key_id            = var.kms_key_arn
            delete_on_termination = true
          }
        }
      }
    }
  }

  tags = {
    Name = var.name
  }
}
