
output "name_servers" {
  value = azurerm_dns_zone.default.name_servers
}

output "postgres_host" {
  value = azurerm_postgresql_server.postgres.fqdn
}

output "key_vault" {
  value = azurerm_key_vault.secrets.name
}
