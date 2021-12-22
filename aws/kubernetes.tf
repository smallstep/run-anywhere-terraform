#----------------------------------------------------------------------------------
# 
# This file is where we set up Kubernetes and related resources
# 
#----------------------------------------------------------------------------------

# The AWS provider only allows us to access secret values with this type of a data source
data "aws_secretsmanager_secret_version" "auth_secret" {
  secret_id = aws_secretsmanager_secret.auth_secret.id
  depends_on = [
    aws_secretsmanager_secret_version.auth_secret
  ]
}

data "aws_secretsmanager_secret_version" "yubihsm_pin" {
  count = var.yubihsm_enabled == true ? 1 : 0

  secret_id = aws_secretsmanager_secret.yubihsm_pin[count.index].id
  depends_on = [
    aws_secretsmanager_secret_version.yubihsm_pin
  ]
}

data "aws_secretsmanager_secret_version" "majordomo_secret" {
  secret_id = aws_secretsmanager_secret.majordomo_secret.id
  depends_on = [
    aws_secretsmanager_secret_version.majordomo_secret
  ]
}

data "aws_secretsmanager_secret_version" "oidc_jwks" {
  secret_id = aws_secretsmanager_secret.oidc_jwks.id
  depends_on = [
    null_resource.generate_oidc_jwk
  ]
}

data "aws_secretsmanager_secret_version" "postgresql_password" {
  secret_id = aws_secretsmanager_secret.master_password_string.id
  depends_on = [
    aws_secretsmanager_secret_version.master_password_string
  ]
}

data "aws_secretsmanager_secret_version" "private_issuer_password" {
  secret_id = aws_secretsmanager_secret.private_issuer_password.id
  depends_on = [
    aws_secretsmanager_secret_version.private_issuer_password
  ]
}

# Temporary key generated by the create_temp_scim_key.sh script
# If using SCIM for provisioning, replace the value in SecretsManager and re-apply
data "aws_secretsmanager_secret_version" "scim_key" {
  secret_id = aws_secretsmanager_secret.scim_key.id
  depends_on = [
    null_resource.generate_temp_scim_key
  ]
}

data "aws_secretsmanager_secret_version" "smtp_password" {
  secret_id = aws_secretsmanager_secret.smtp_password.id
  depends_on = [
    aws_secretsmanager_secret_version.smtp_password
  ]
}

resource "kubernetes_namespace" "install_namespace" {
  metadata {
    name = var.k8s_namespace

    annotations = {
      "linkerd.io/inject" = "enabled"
    }
  }
}

resource "kubernetes_secret" "auth" {
  metadata {
    name      = "auth"
    namespace = var.k8s_namespace
  }
  data = {
    secret = data.aws_secretsmanager_secret_version.auth_secret.secret_string
  }
}

resource "kubernetes_secret" "yubihsm_pin" {
  count = var.yubihsm_enabled == true ? 1 : 0

  metadata {
    name      = "yubihsm2-pin"
    namespace = var.k8s_namespace
  }
  data = {
    "pin.txt" = data.aws_secretsmanager_secret_version.yubihsm_pin[count.index].secret_string
  }
}

resource "kubernetes_secret" "majordomo" {
  metadata {
    name      = "majordomo-provisioner-password"
    namespace = var.k8s_namespace
  }
  data = {
    password = data.aws_secretsmanager_secret_version.majordomo_secret.secret_string
  }
}

resource "kubernetes_secret" "oidc" {
  metadata {
    name      = "oidc"
    namespace = var.k8s_namespace
  }
  data = {
    jwks = data.aws_secretsmanager_secret_version.oidc_jwks.secret_string
  }
}

resource "kubernetes_secret" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = var.k8s_namespace
  }
  data = {
    password = data.aws_secretsmanager_secret_version.postgresql_password.secret_string
  }
}

resource "kubernetes_secret" "private_issuer" {
  metadata {
    name      = "private-issuer"
    namespace = var.k8s_namespace
  }
  data = {
    password = data.aws_secretsmanager_secret_version.private_issuer_password.secret_string
  }
}

resource "kubernetes_secret" "scim" {
  metadata {
    name      = "scim-server-secrets"
    namespace = var.k8s_namespace
  }
  data = {
    "credentials.json" = data.aws_secretsmanager_secret_version.scim_key.secret_string
  }
}

resource "kubernetes_secret" "smtp" {
  metadata {
    name      = "smtp"
    namespace = var.k8s_namespace
  }
  data = {
    password = data.aws_secretsmanager_secret_version.smtp_password.secret_string
  }
}
