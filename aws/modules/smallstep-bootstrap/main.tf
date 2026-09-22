# Pre-KOTS bootstrap: the namespace, the databases, and the Kubernetes
# Secrets the Smallstep platform expects to find when the KOTS install starts.
# Everything here must exist BEFORE kots-install.sh runs; nothing here may
# depend on anything the app deploys.
#
# Secrets never pass through Terraform. Stage 1 wrote them to Secrets Manager;
# this module names their ARNs into a script, and a Job fetches them at run
# time under its own IRSA identity. A Terraform data source would be shorter
# and would also copy every credential into this stage's state file in
# plaintext.
#
# The Job is a chain of initContainers plus one main container, each running
# one stage of the same rendered script. Chained initContainers over one
# mega-image keeps every stage on a pinned public image: the aws-cli image
# fetches, postgres/psql seeds the databases, step-cli generates key material,
# and kubectl publishes the results as Secrets. Sequencing is the Job's — a
# stage only runs after the previous one succeeded, and backoffLimit retries
# the whole chain, which every stage tolerates by design (see the script's
# idempotence notes).

locals {
  # Each stage's image, pinned by tag. Bumping one tool means bumping one tag
  # in a plan diff — the same reviewability argument that pinned the chart
  # versions in the root.
  image_aws_cli  = "public.ecr.aws/aws-cli/aws-cli:2.22.0"
  image_postgres = "postgres:16-alpine"
  image_step_cli = "smallstep/step-cli:0.28.0"
  # bitnamilegacy, not bitnami: the bitnami/kubectl tags were removed from
  # Bitnami's catalog in 2025. bitnamilegacy is Bitnami's frozen archive of
  # the same image (bash at /bin/bash, kubectl on PATH, uid 1001) — it
  # receives no updates, which this module accepts.
  image_kubectl = "bitnamilegacy/kubectl:1.31"

  script = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    region      = var.region
    namespace   = var.namespace
    rds_host    = var.rds_host
    rds_port    = var.rds_port
    secret_arns = var.app_secret_arns
  })

  # Baked into the Job's pod template as a label. Job specs are immutable, so
  # a changed hash forces the provider to replace the Job — which is the only
  # way "the script changed" becomes "the bootstrap re-ran".
  script_hash = substr(sha256(local.script), 0, 8)
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/part-of" = var.name
    }
  }

  # KOTS stamps its own metadata on the app namespace. Terraform reverting it
  # on the next apply would silently undo work it cannot see the point of.
  lifecycle {
    ignore_changes = [metadata[0].annotations, metadata[0].labels]
  }
}

resource "kubernetes_service_account_v1" "bootstrap" {
  metadata {
    # Pinned by the IRSA role's trust policy (<namespace>:smallstep-bootstrap)
    # — rename it there or nowhere.
    name      = "smallstep-bootstrap"
    namespace = kubernetes_namespace_v1.this.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = var.bootstrap_role_arn
    }
  }
}

resource "kubernetes_role_v1" "bootstrap" {
  metadata {
    name      = "smallstep-bootstrap"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  # Exactly what `kubectl apply` and create-if-absent need: get to probe,
  # create for first runs, patch for convergence. A namespaced Role, not a
  # ClusterRole — this identity can touch secrets in the app namespace and
  # nowhere else. `create` cannot be scoped by resourceName (a Kubernetes RBAC
  # limitation, not an oversight), which is why the verb list is tight instead.
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "create", "patch"]
  }
}

resource "kubernetes_role_binding_v1" "bootstrap" {
  metadata {
    name      = "smallstep-bootstrap"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.bootstrap.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.bootstrap.metadata[0].name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }
}

resource "kubernetes_config_map_v1" "bootstrap" {
  metadata {
    name      = "smallstep-bootstrap"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  data = {
    "bootstrap.sh" = local.script
  }
}

resource "kubernetes_job_v1" "bootstrap" {
  metadata {
    name      = "smallstep-bootstrap"
    namespace = kubernetes_namespace_v1.this.metadata[0].name

    labels = {
      "app.kubernetes.io/name"    = "smallstep-bootstrap"
      "app.kubernetes.io/part-of" = var.name
      "script-hash"               = local.script_hash
    }
  }

  spec {
    backoff_limit = 3

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "smallstep-bootstrap"
          # The load-bearing copy of the hash: pod template labels are part of
          # the immutable Job spec, so changing this replaces the Job. The
          # metadata label above is cosmetic (mutable) — this one re-runs the
          # bootstrap.
          "script-hash" = local.script_hash
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.bootstrap.metadata[0].name
        restart_policy       = "Never"

        # Container uids are pinned to match the chown handoff in the
        # fetch-secrets stage: /work/secrets goes to 1001 (the kubectl
        # container that reads it), /work/gen to 1000 (the step-cli container
        # that writes it). Pinning here keeps the contract true even when an
        # image's default USER drifts under a tag bump.

        init_container {
          name  = "fetch-secrets"
          image = local.image_aws_cli

          command = ["/bin/bash", "/bootstrap/bootstrap.sh", "fetch-secrets"]

          # Root, so it can hand the fetched files to the uids downstream
          # containers run as. 0600 files owned by root are unreadable to
          # them, and the resulting "Permission denied" points at the wrong
          # container entirely.
          security_context {
            run_as_user = 0
          }

          volume_mount {
            name       = "work"
            mount_path = "/work"
          }
          volume_mount {
            name       = "bootstrap"
            mount_path = "/bootstrap"
            read_only  = true
          }
        }

        init_container {
          name  = "init-db"
          image = local.image_postgres

          command = ["/bin/bash", "/bootstrap/bootstrap.sh", "init-db"]

          security_context {
            run_as_user = 0
          }

          volume_mount {
            name       = "work"
            mount_path = "/work"
          }
          volume_mount {
            name       = "bootstrap"
            mount_path = "/bootstrap"
            read_only  = true
          }
        }

        init_container {
          name  = "gen-material"
          image = local.image_step_cli

          command = ["/bin/bash", "/bootstrap/bootstrap.sh", "gen-material"]

          # The step-cli image's own user.
          security_context {
            run_as_user     = 1000
            run_as_non_root = true
          }

          volume_mount {
            name       = "work"
            mount_path = "/work"
          }
          volume_mount {
            name       = "bootstrap"
            mount_path = "/bootstrap"
            read_only  = true
          }
        }

        container {
          name  = "apply-secrets"
          image = local.image_kubectl

          command = ["/bin/bash", "/bootstrap/bootstrap.sh", "apply-secrets"]

          # The bitnamilegacy/kubectl image's own non-root user, pinned here
          # so the chown handoff stays true even if the image default drifts.
          security_context {
            run_as_user     = 1001
            run_as_non_root = true
          }

          volume_mount {
            name       = "work"
            mount_path = "/work"
          }
          volume_mount {
            name       = "bootstrap"
            mount_path = "/bootstrap"
            read_only  = true
          }
        }

        volume {
          name = "work"

          empty_dir {
            # Secrets pass through here. In memory means they never touch a
            # node's disk.
            medium = "Memory"
          }
        }

        volume {
          name = "bootstrap"

          config_map {
            name         = kubernetes_config_map_v1.bootstrap.metadata[0].name
            default_mode = "0555"
          }
        }
      }
    }
  }

  # Block the apply until the bootstrap succeeds: kots-install runs next and
  # assumes every Secret and database exists. A green apply beside a failed
  # bootstrap would move this failure into the KOTS deploy, where it reads as
  # anything but what it is.
  wait_for_completion = true

  timeouts {
    create = "15m"
    update = "15m"
  }

  depends_on = [
    kubernetes_role_binding_v1.bootstrap,
  ]
}
