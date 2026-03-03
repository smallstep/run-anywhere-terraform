
resource "random_password" "postgres" {
  length           = 10
  min_upper        = 1
  min_special      = 1
  special          = true
  override_special = "$@!"
}

resource "azurerm_key_vault_secret" "postgres" {
  name         = "postgres"
  value        = random_password.postgres.result
  key_vault_id = azurerm_key_vault.secrets.id
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                = "smallstep"
  resource_group_name = azurerm_resource_group.smallstep.name
  location            = azurerm_resource_group.smallstep.location

  administrator_login    = "postgres"
  administrator_password = azurerm_key_vault_secret.postgres.value

  sku_name = "GP_Standard_D2s_v3"
  version  = "15"

  storage_mb                   = 32768
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false
  # TODO use private endpoint with delegated subnet
  public_network_access_enabled = true

  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_only" {
  name             = "azure"
  server_id        = azurerm_postgresql_flexible_server.postgres.id
  # 0.0.0.0/32 allows access to all Azure services
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_configuration" "azure_extensions" {
  name      = "azure.extensions"
  server_id = azurerm_postgresql_flexible_server.postgres.id
  value     = "PGCRYPTO,UUID-OSSP,BTREE_GIN"
}
