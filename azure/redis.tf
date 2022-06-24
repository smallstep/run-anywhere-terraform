
resource "azurerm_redis_cache" "smallstep" {
  name                = "smallstep"
  resource_group_name = azurerm_resource_group.smallstep.name
  location            = azurerm_resource_group.smallstep.location

  family     = "C"
  sku_name   = "Standard"
  capacity   = 1
  
  enable_non_ssl_port               = false
  minimum_tls_version               = "1.2"
  public_network_access_enabled     = false
  redis_version                     = 6
}

resource "azurerm_private_endpoint" "redis" {
  name                = "redis"
  resource_group_name = azurerm_resource_group.smallstep.name
  location            = azurerm_resource_group.smallstep.location
  subnet_id           = azurerm_subnet.default.id

  private_service_connection {
    name = "redis"
    is_manual_connection = false
    private_connection_resource_id = azurerm_redis_cache.smallstep.id
    subresource_names = ["redisCache"]
  }
}

output "redis_private_ip" {
  value = azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address
}

output "redis_url" {
  value = azurerm_redis_cache.smallstep.primary_connection_string
}
