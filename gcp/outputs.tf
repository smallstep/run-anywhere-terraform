#-------------------------------------------------------------------------------------- 
# 
# This file hosts all output resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

output "dns_api_domain" {
  value = trimsuffix(google_dns_record_set.web_api.name, ".")
}

output "dns_base_domain" {
  value = trimsuffix(google_dns_managed_zone.default.dns_name, ".")
}

output "dns_gateway_domain" {
  value = trimsuffix(google_dns_record_set.web_api_gateway.name, ".")
}

output "dns_name_servers" {
  value = google_dns_managed_zone.default.name_servers
}

output "dns_scim_domain" {
  value = trimsuffix(google_dns_record_set.web_api_scim.name, ".")
}

output "dns_linkedca_domain" {
  value = trimsuffix(google_dns_record_set.api_linkedca.name, ".")
}

output "dns_zone" {
  value = google_dns_managed_zone.default.dns_name
}

output "gsuite_service_account_id" {
  value = google_service_account.scim_server.unique_id
}

output "project_id" {
  value = var.project_id
}

output "redis_addr" {
  value = "${google_redis_instance.smallstep.host}:${google_redis_instance.smallstep.port}"
}

output "redis_host" {
  value = google_redis_instance.smallstep.host
}

output "redis_port" {
  value = google_redis_instance.smallstep.port
}

output "reserved_peering_ranges" {
  value = google_compute_global_address.service_allocation.name
}

output "service_account_landlord" {
  value = google_service_account.landlord.email
}

output "service_account_magpie" {
  value = google_service_account.magpie.email
}

output "smallstep_ingress" {
  value = google_compute_address.smallstep_address.address
}

output "sql_master_host" {
  value = google_sql_database_instance.master.private_ip_address
}

output "sql_master_host_public" {
  value = google_sql_database_instance.master.public_ip_address
}

output "sql_db_web_user" {
  value = google_sql_user.postgres.name
}