
resource "random_id" "kms" {
  byte_length = 8
  prefix      = "kms-"
}

resource "azurerm_key_vault" "kms" {
  name                        = random_id.kms.id
  resource_group_name = azurerm_resource_group.smallstep.name
  location            = azurerm_resource_group.smallstep.location
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
