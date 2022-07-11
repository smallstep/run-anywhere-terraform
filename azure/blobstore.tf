resource "random_id" "veto_crl" {
  byte_length = 2
  prefix      = "crl"
}

resource "azurerm_storage_account" "default" {
  name                      = random_id.veto_crl.hex
  resource_group_name       = azurerm_resource_group.smallstep.name
  location                  = azurerm_resource_group.smallstep.location
  account_tier              = "Standard"
  account_replication_type  = "LRS"
  enable_https_traffic_only = false

  depends_on = [azurerm_dns_cname_record.crl]

  custom_domain {
    name          = trim("crl.${azurerm_dns_zone.default.name}", ".")
    use_subdomain = false
  }
}

resource "azurerm_storage_container" "crls" {
  name                  = "crls"
  storage_account_name  = azurerm_storage_account.default.name
  container_access_type = "blob"
}

resource "azurerm_key_vault_secret" "storage_key" {
  name         = "storage-key"
  value        = azurerm_storage_account.default.primary_access_key
  key_vault_id = azurerm_key_vault.secrets.id
}
