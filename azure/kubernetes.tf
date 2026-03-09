resource "kubernetes_namespace_v1" "smallstep" {
  metadata {
    name = var.namespace

    annotations = {
      "linkerd.io/inject" = "enabled"
    }
  }
}
