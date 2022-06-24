
resource "kubernetes_namespace" "smallstep" {
  metadata {
    name = var.namespace

    annotations = {
      "linkerd.io/inject" = "enabled"
    }
  }
}
