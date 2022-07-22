
output "name_servers" {
  value = azurerm_dns_zone.default.name_servers
}

output "postgres_host" {
  value = azurerm_postgresql_server.postgres.fqdn
}

output "kms_vault" {
  value = azurerm_key_vault.kms.name
}

output "redis_private_ip" {
  value = azurerm_private_endpoint.redis.private_service_connection[0].private_ip_address
}

output "redis_url" {
  value = azurerm_redis_cache.smallstep.primary_connection_string
}

output "primary_blob_host" {
  value = azurerm_storage_account.default.primary_blob_host
}

output "azure_storage_key" {
  value     = azurerm_storage_account.default.primary_access_key
  sensitive = true
}
