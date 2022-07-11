
resource "azurerm_public_ip" "smallstep_address" {
  name                = "smallstep_address"
  resource_group_name = azurerm_resource_group.smallstep.name
  location            = azurerm_resource_group.smallstep.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_dns_zone" "default" {
  name                = var.base_domain
  resource_group_name = azurerm_resource_group.smallstep.name
}

resource "azurerm_dns_a_record" "web_api" {
  name                = "api"
  zone_name           = azurerm_dns_zone.default.name
  resource_group_name = azurerm_resource_group.smallstep.name
  ttl                 = 300
  records             = [azurerm_public_ip.smallstep_address.ip_address]
}

resource "azurerm_dns_a_record" "web_auth" {
  name                = "auth"
  zone_name           = azurerm_dns_zone.default.name
  resource_group_name = azurerm_resource_group.smallstep.name
  ttl                 = 300
  records             = [azurerm_public_ip.smallstep_address.ip_address]
}

resource "azurerm_dns_a_record" "web_api_scim" {
  name                = "scim.api"
  zone_name           = azurerm_dns_zone.default.name
  resource_group_name = azurerm_resource_group.smallstep.name
  ttl                 = 300
  records             = [azurerm_public_ip.smallstep_address.ip_address]
}

resource "azurerm_dns_a_record" "web_api_gateway" {
  name                = "gateway.api"
  zone_name           = azurerm_dns_zone.default.name
  resource_group_name = azurerm_resource_group.smallstep.name
  ttl                 = 300
  records             = [azurerm_public_ip.smallstep_address.ip_address]
}

resource "azurerm_dns_a_record" "web_app" {
  name                = "app"
  zone_name           = azurerm_dns_zone.default.name
  resource_group_name = azurerm_resource_group.smallstep.name
  ttl                 = 300
  records             = [azurerm_public_ip.smallstep_address.ip_address]
}

resource "azurerm_dns_a_record" "web_scif" {
  name                = "scif.infra"
  zone_name           = azurerm_dns_zone.default.name
  resource_group_name = azurerm_resource_group.smallstep.name
  ttl                 = 300
  records             = [azurerm_public_ip.smallstep_address.ip_address]
}

resource "azurerm_dns_a_record" "landlord_teams" {
  name                = "*.ca"
  zone_name           = azurerm_dns_zone.default.name
  resource_group_name = azurerm_resource_group.smallstep.name
  ttl                 = 300
  records             = [azurerm_public_ip.smallstep_address.ip_address]
}

resource "azurerm_dns_a_record" "tunnel" {
  name                = "tunnel"
  zone_name           = azurerm_dns_zone.default.name
  resource_group_name = azurerm_resource_group.smallstep.name
  ttl                 = 300
  records             = [azurerm_public_ip.smallstep_address.ip_address]
}

resource "azurerm_dns_a_record" "ocsp" {
  name                = "ocsp"
  zone_name           = azurerm_dns_zone.default.name
  resource_group_name = azurerm_resource_group.smallstep.name
  ttl                 = 300
  records             = [azurerm_public_ip.smallstep_address.ip_address]
}

resource "azurerm_dns_cname_record" "crl" {
  name                = "crl"
  zone_name           = azurerm_dns_zone.default.name
  resource_group_name = azurerm_resource_group.smallstep.name
  ttl                 = 300
  record              = "${random_id.veto_crl.hex}.blob.core.windows.net"
}

resource "azurerm_dns_a_record" "approvalq" {
  name                = "approvalq.infra"
  zone_name           = azurerm_dns_zone.default.name
  resource_group_name = azurerm_resource_group.smallstep.name
  ttl                 = 300
  records             = [azurerm_public_ip.smallstep_address.ip_address]
}
