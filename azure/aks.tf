
resource "azurerm_kubernetes_cluster" "primary" {
  name                      = var.k8s_cluster_name
  location                  = azurerm_resource_group.smallstep.location
  resource_group_name       = azurerm_resource_group.smallstep.name
  automatic_channel_upgrade = "stable"
  dns_prefix                = var.k8s_cluster_name

  default_node_pool {
    name            = "default"
    node_count      = 2
    vm_size         = "Standard_D2_v2"
    os_disk_size_gb = 30
    vnet_subnet_id           = azurerm_subnet.default.id
  }

  identity {
    type = "SystemAssigned"
  }
}