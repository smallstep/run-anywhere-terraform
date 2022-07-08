resource "random_id" "veto_crl" {
  byte_length = 2
  prefix      = "crl"
}

resource "azurerm_storage_account" "default" {
  name                     = random_id.veto_crl.hex
  resource_group_name      = azurerm_resource_group.smallstep.name
  location                 = azurerm_resource_group.smallstep.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  enable_https_traffic_only = false

  depends_on = [azurerm_dns_cname_record.crl]

  custom_domain {
    name          = trim("crl.${azurerm_dns_zone.default.name}", ".")
    use_subdomain = false
  }
}
