resource "random_string" "network" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_virtual_network" "default" {
  name                = "${random_string.network.result}-network"
  address_space       = ["10.2.0.0/16"]
  resource_group_name = azurerm_resource_group.smallstep.name
  location            = azurerm_resource_group.smallstep.location
}

resource "azurerm_subnet" "default" {
  name                 = "${random_string.network.result}-subnet"
  resource_group_name  = azurerm_resource_group.smallstep.name
  virtual_network_name = azurerm_virtual_network.default.name
  address_prefixes     = ["10.2.1.0/24"]

  enforce_private_link_endpoint_network_policies = false
}

