
resource "azurerm_redis_cache" "smallstep" {
  name                = "smallstep"
  resource_group_name = azurerm_resource_group.smallstep.name
  location            = azurerm_resource_group.smallstep.location

  family   = "C"
  sku_name = "Standard"
  capacity = 1

  enable_non_ssl_port           = false
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false
  redis_version                 = var.redis_version
}

resource "azurerm_private_endpoint" "redis" {
  name                = "redis"
  resource_group_name = azurerm_resource_group.smallstep.name
  location            = azurerm_resource_group.smallstep.location
  subnet_id           = azurerm_subnet.default.id

  private_service_connection {
    name                           = "redis"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_redis_cache.smallstep.id
    subresource_names              = ["redisCache"]
  }
}

# TODO use private DNS since the IP of the private endpoint can change
resource "kubernetes_config_map_v1" "coredns_custom" {
  metadata {
    name      = "coredns-custom"
    namespace = "kube-system"
  }

  data = {
    "redis.override" = <<EOF
hosts {
  ${azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address} ${azurerm_redis_cache.smallstep.hostname}
  fallthrough
}
EOF
  }
}
