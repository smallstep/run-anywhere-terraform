
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

resource "azurerm_postgresql_server" "postgres" {
  name                = "smallstep"
  resource_group_name = azurerm_resource_group.smallstep.name
  location            = azurerm_resource_group.smallstep.location

  administrator_login          = "postgres"
  administrator_login_password = azurerm_key_vault_secret.postgres.value

  sku_name   = "GP_Gen5_2"
  storage_mb = 5120
  version    = "11"

  auto_grow_enabled                 = true
  backup_retention_days             = 7
  geo_redundant_backup_enabled      = false
  # TODO use private endpoint
  public_network_access_enabled     = true
  ssl_enforcement_enabled           = true
  ssl_minimal_tls_version_enforced  = "TLS1_2"
}

resource "azurerm_postgresql_firewall_rule" "azure_only" {
  name                = "azure"
  resource_group_name = azurerm_resource_group.smallstep.name
  server_name         = azurerm_postgresql_server.postgres.name
  # 0.0.0.0/32 allows access to all Azure services
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}
