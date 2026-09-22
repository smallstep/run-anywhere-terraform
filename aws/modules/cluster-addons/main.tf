# Cluster add-ons: the in-cluster machinery the KOTS app assumes exists but
# does not ship. Three things — a load balancer controller the app's Service
# annotations name explicitly, a default StorageClass for kotsadm's PVC, and
# a log shipper for SIEM ingestion.
#
# Just as important is what is deliberately NOT here. cert-manager,
# ingress-nginx, trust-manager and the Smallstep issuer are all bundled in the
# KOTS release; installing them a second time from upstream charts fights the
# bundled copies over CRD ownership and webhook configuration, and the loss
# presents as unrelated app failures long after this apply went green. And no
# external-dns: exactly one DNS record needs to track a load balancer the
# application creates (control.infra), and a one-record post-install step does
# that without a controller, its IRSA role, and its CRD surface.

# The KOTS app's lobby Service is annotated for THIS controller and no other:
# aws-load-balancer-type "external", nlb-target-type "ip", scheme
# internet-facing, and an explicit list of EIP allocations (stage 1's lobby
# EIPs — the static ingress IPs a downstream firewall can pin). The legacy
# in-tree cloud provider ignores every one of those annotations, so without
# this controller the lobby Service sits <pending> forever and the KOTS
# install stalls at "waiting for load balancer". It must be healthy BEFORE
# the application is installed; check it rather than discovering it 20 minutes
# into a hung deploy.
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.lb_controller_chart_version
  namespace  = "kube-system"

  # Fail the apply if the controller does not come up. A green apply beside a
  # crash-looping controller would push the failure into kots-install, where
  # it is much harder to read.
  wait    = true
  timeout = 600

  values = [yamlencode({
    clusterName = var.cluster_name

    # region and vpcId are supplied rather than discovered — belt and braces,
    # not necessity: modules/eks pins the IMDSv2 hop limit at 2 precisely so
    # pods keep IMDS access, but the controller's metadata discovery can still
    # flake, and that failure presents as a crash loop with a misleading
    # "failed to introspect region" error. Explicit values remove the
    # discovery path entirely.
    region = var.region
    vpcId  = var.vpc_id

    serviceAccount = {
      create = true
      # Not a free choice: the IRSA role's trust policy pins
      # kube-system:aws-load-balancer-controller.
      name = "aws-load-balancer-controller"
      annotations = {
        "eks.amazonaws.com/role-arn" = var.lb_controller_role_arn
      }
    }
  })]
}

# kotsadm's rqlite datastore claims a PVC with no storageClassName, which only
# binds if the cluster has a default StorageClass. EKS ships gp2 (in-tree
# provisioner, unencrypted); this deployment wants gp3 on the EBS CSI driver with
# encryption on — so gp3 is created as the default and gp2 is explicitly
# demoted below. Two classes both claiming default is undefined behavior:
# which one a PVC binds to depends on admission ordering, and the failure is
# an intermittently unencrypted volume rather than an error.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"

  # WaitForFirstConsumer, not Immediate: the volume must be created in the AZ
  # of the node that schedules the pod, or a 3-AZ cluster binds volumes to
  # zones with no matching pod and the PVC deadlocks.
  volume_binding_mode = "WaitForFirstConsumer"

  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
    # The platform CMK, by full ARN. encrypted="true" alone encrypts under
    # the AWS-managed aws/ebs key — silently outside the CMK-everywhere
    # posture the IAM grants (ebs_csi_kms_cmk_ids) were written for. Note
    # StorageClass parameters are immutable: changing this replaces the class
    # (harmless — classes hold no state), and volumes already provisioned
    # under the old key stay there until re-provisioned.
    kmsKeyId = var.kms_key_arn
  }
}

resource "kubernetes_annotations" "gp2_not_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"

  metadata {
    name = "gp2"
  }

  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }

  # The EKS addon manager owns this annotation under its own field manager;
  # without force the patch fails with a field-ownership conflict.
  force = true
}

# Log shipping for SIEM ingestion. Structured JSON container logs from every
# pod ship to the CMK-encrypted CloudWatch log group stage 1 created; route
# that stream on to a SIEM from there.
#
# Count-gated on the log group name: stage 1 emits "" when enable_logging is
# off, and shipping logs to a group that doesn't exist (autoCreateGroup is
# false on purpose — the group's retention and CMK encryption are Terraform's
# to manage, not fluent-bit's) would just crash-loop the daemonset.
resource "helm_release" "aws_for_fluent_bit" {
  count = var.container_log_group_name != "" ? 1 : 0

  name       = "aws-for-fluent-bit"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-for-fluent-bit"
  version    = var.fluent_bit_chart_version
  namespace  = "kube-system"

  wait    = true
  timeout = 600

  values = [yamlencode({
    serviceAccount = {
      create = true
      # Pinned by the IRSA trust policy (kube-system:fluent-bit) — the chart's
      # default name follows the release name and would silently fail STS
      # AssumeRoleWithWebIdentity.
      name = "fluent-bit"
      annotations = {
        "eks.amazonaws.com/role-arn" = var.fluent_bit_role_arn
      }
    }

    cloudWatchLogs = {
      enabled         = true
      region          = var.region
      logGroupName    = var.container_log_group_name
      autoCreateGroup = false
      # Set explicitly to empty: when logGroupTemplate is non-empty the chart
      # prefers it over logGroupName, and logs scatter across auto-derived
      # per-namespace groups outside the encrypted one above.
      logGroupTemplate = ""
    }

    # cloudWatchLogs (the C plugin) is the one output in use. cloudWatch is
    # the deprecated Go plugin for the same destination — disabled so the two
    # can never double-ship; the rest are destinations this deployment does not have.
    cloudWatch    = { enabled = false }
    firehose      = { enabled = false }
    kinesis       = { enabled = false }
    elasticsearch = { enabled = false }
  })]
}
