
resource "random_id" "key_vault" {
  byte_length = 4
  prefix      = "smallstep-"
}

resource "azurerm_key_vault" "secrets" {
  name                        = random_id.key_vault.id
  resource_group_name         = azurerm_resource_group.smallstep.name
  location                    = azurerm_resource_group.smallstep.location
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  enable_rbac_authorization   = false

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    secret_permissions = [
      "Get",
      "Delete",
      "List",
      "Set",
    ]
  }
}

resource "kubernetes_secret" "postgres" {
  metadata {
    name      = "postgresql"
    namespace = "smallstep"
  }

  data = {
    username = "postgres"
    password = azurerm_key_vault_secret.postgres.value
  }
}

resource "random_password" "veneer_auth" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "veneer_auth" {
  name         = "veneer-auth"
  key_vault_id = azurerm_key_vault.secrets.id
  value        = random_password.veneer_auth.result
}

resource "kubernetes_secret" "veneer_auth" {
  metadata {
    name      = "auth"
    namespace = var.namespace
  }

  data = {
    secret = azurerm_key_vault_secret.veneer_auth.value
  }
}

resource "null_resource" "generate_oidc_jwk" {
  provisioner "local-exec" {
    command = "${path.module}/scripts/create_oidc_secret.sh"

    environment = {
      VAULT = azurerm_key_vault.secrets.name
    }
  }
}

data "azurerm_key_vault_secret" "oidcjwk" {
  name         = "oidcjwk"
  key_vault_id = azurerm_key_vault.secrets.id
  depends_on   = [null_resource.generate_oidc_jwk]
}

resource "kubernetes_secret" "oidc" {
  metadata {
    name      = "oidc"
    namespace = var.namespace
  }
  data = {
    jwks = data.azurerm_key_vault_secret.oidcjwk.value
  }
}

resource "azurerm_key_vault_secret" "private_issuer_password" {
  name         = "private-issuer-password"
  value        = var.private_issuer_password
  key_vault_id = azurerm_key_vault.secrets.id

  # This variable will only be set the first time running terraform and will change to ""
  # Don't wipe the password when this happens
  lifecycle {
    ignore_changes = [value]
  }
}

resource "kubernetes_secret" "private_issuer" {
  metadata {
    name      = "private-issuer"
    namespace = var.namespace
  }
  data = {
    password = azurerm_key_vault_secret.private_issuer_password.value
  }
}

resource "azurerm_key_vault_secret" "smtp_password" {
  name         = "smtp-password"
  key_vault_id = azurerm_key_vault.secrets.id
  value        = var.smtp_password

  # This variable will only be set the first time running terraform and will change to ""
  # Don't wipe the password when this happens
  lifecycle {
    ignore_changes = [value]
  }
}

resource "kubernetes_secret" "smtp_password" {
  metadata {
    name      = "smtp"
    namespace = "smallstep"
  }

  data = {
    password = azurerm_key_vault_secret.smtp_password.value
  }
}

# This (optional) secret is set by the user by specifying the value of variable yubihsm_pin in an apply
resource "azurerm_key_vault_secret" "yubihsm_pin" {
  count = var.yubihsm_enabled == true ? 1 : 0

  name         = "hsm-pin"
  key_vault_id = azurerm_key_vault.secrets.id
  value        = var.yubihsm_pin

  # This variable will only be set the first time running terraform and will change to ""
  # Don't wipe the password when this happens
  lifecycle {
    ignore_changes = [value]
  }
}

resource "kubernetes_secret" "yubihsm_pin" {
  count = var.yubihsm_enabled == true ? 1 : 0

  metadata {
    name      = "yubihsm2-pin"
    namespace = var.namespace
  }
  data = {
    "pin.txt" = azurerm_key_vault_secret.yubihsm_pin[count.index].value
  }
}


# Randomly generated password for majordomo
resource "random_password" "majordomo_provisioner_password" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "majordomo_provisioner_password" {
  name         = "majordomo-provisioner-password"
  key_vault_id = azurerm_key_vault.secrets.id
  value        = random_password.majordomo_provisioner_password.result
}

resource "kubernetes_secret" "majordomo_provisioner_password" {
  metadata {
    name      = "majordomo-provisioner-password"
    namespace = var.namespace
  }

  data = {
    password = azurerm_key_vault_secret.majordomo_provisioner_password.value
  }
}

# TODO
resource "kubernetes_secret" "scim-server-credentials" {
  metadata {
    name      = "scim-server-secrets"
    namespace = var.namespace
  }

  data = {
    "credentials.json" = ""
  }
}

resource "kubernetes_secret" "azure_storage_key" {
  metadata {
    name      = "azure-storage-key"
    namespace = var.namespace
  }

  data = {
    "AZURE_STORAGE_KEY" = azurerm_key_vault_secret.storage_key.value
  }
}
