#-------------------------------------------------------------------------------------- 
# 
# This file hosts all Kubernetes resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

data "google_kms_secret" "auth_secret" {
  crypto_key = data.google_kms_crypto_key.terraform_secret.id
  ciphertext = filebase64("${var.path_to_secrets}/auth_secret.enc")
}

data "google_kms_secret" "majordomo_provisioner_password" {
  crypto_key = data.google_kms_crypto_key.terraform_secret.id
  ciphertext = filebase64("${var.path_to_secrets}/majordomo-provisioner-password_password.enc")
}

data "google_kms_secret" "oidc_jwks" {
  crypto_key = data.google_kms_crypto_key.terraform_secret.id
  ciphertext = filebase64("${var.path_to_secrets}/oidc_jwks.enc")
}

data "google_kms_secret" "smtp_password" {
  crypto_key = data.google_kms_crypto_key.terraform_secret.id
  ciphertext = filebase64("${var.path_to_secrets}/smtp_password.enc")
}

data "google_kms_secret" "private_issuer_password" {
  crypto_key = data.google_kms_crypto_key.terraform_secret.id
  ciphertext = filebase64("${var.path_to_secrets}/private-issuer_password.enc")
}

data "google_kms_secret" "yubihsm2_pin" {
  crypto_key = data.google_kms_crypto_key.terraform_secret.id
  ciphertext = filebase64("${var.path_to_secrets}/yubihsm2_pin.enc")
}

resource "kubernetes_namespace" "install_namespace" {
  metadata {
    name = var.namespace

    annotations = {
      "linkerd.io/inject" = "enabled"
    }
  }

  depends_on  = [google_container_cluster.primary]
}

resource "kubernetes_secret" "scim-server-credentials" {
  metadata {
    name      = "scim-server-secrets"
    namespace = var.namespace
  }
  data = {
    "credentials.json" = base64decode(google_service_account_key.scim_server_key.private_key)
  }
  depends_on  = [google_container_cluster.primary, kubernetes_namespace.install_namespace]
}

resource "kubernetes_secret" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = var.namespace
  }
  data = {
    password = data.google_kms_secret.postgresql_password.plaintext
  }
  depends_on  = [google_container_cluster.primary, kubernetes_namespace.install_namespace]
}

resource "kubernetes_secret" "auth" {
  metadata {
    name      = "auth"
    namespace = var.namespace
  }
  data = {
    secret = data.google_kms_secret.auth_secret.plaintext
  }
  depends_on  = [google_container_cluster.primary, kubernetes_namespace.install_namespace]
}

resource "kubernetes_secret" "majordomo-provisioner-password" {
  metadata {
    name      = "majordomo-provisioner-password"
    namespace = var.namespace
  }
  data = {
    password = data.google_kms_secret.majordomo_provisioner_password.plaintext
  }
  depends_on  = [google_container_cluster.primary, kubernetes_namespace.install_namespace]
}

resource "kubernetes_secret" "oidc" {
  metadata {
    name      = "oidc"
    namespace = var.namespace
  }
  data = {
    jwks = data.google_kms_secret.oidc_jwks.plaintext
  }
  depends_on  = [google_container_cluster.primary, kubernetes_namespace.install_namespace]
}

resource "kubernetes_secret" "smtp" {
  metadata {
    name      = "smtp"
    namespace = var.namespace
  }
  data = {
    password = data.google_kms_secret.smtp_password.plaintext
  }
  depends_on  = [google_container_cluster.primary, kubernetes_namespace.install_namespace]
}

resource "kubernetes_secret" "private_issuer" {
  metadata {
    name      = "private-issuer"
    namespace = var.namespace
  }
  data = {
    password = data.google_kms_secret.private_issuer_password.plaintext
  }
  depends_on  = [google_container_cluster.primary, kubernetes_namespace.install_namespace]
}

resource "kubernetes_secret" "yubihsm2_pin" {
  metadata {
    name      = "yubihsm2-pin"
    namespace = var.namespace
  }
  data = {
    "pin.txt" = data.google_kms_secret.private_issuer_password.plaintext
  }
  depends_on  = [google_container_cluster.primary, kubernetes_namespace.install_namespace]
}
