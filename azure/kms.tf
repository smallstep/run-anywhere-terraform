
resource "random_id" "kms" {
  byte_length = 8
  prefix      = "kms-"
}

resource "azurerm_key_vault" "kms" {
  name                        = random_id.kms.id
  resource_group_name         = azurerm_resource_group.smallstep.name
  location                    = azurerm_resource_group.smallstep.location
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false
  sku_name                    = "standard"
  enable_rbac_authorization   = true
}

resource "azurerm_key_vault_key" "gateway_jwt_signing_key" {
  name         = "gateway-jwt-signing-key"
  key_vault_id = azurerm_key_vault.kms.id
  key_type     = "EC"
  curve = "P-256"

  key_opts = [
    "sign",
  ]
}
