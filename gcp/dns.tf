#-------------------------------------------------------------------------------------- 
# 
# This file hosts all DNS resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

resource "google_dns_managed_zone" "default" {
  project     = var.project_id
  depends_on  = [google_project_service.dns]
  name        = "default"
  dns_name    = "${var.base_domain}."
  description = "Certificates aren't hard."
}

resource "google_dns_record_set" "web_api" {
  project      = var.project_id
  name         = "api.${google_dns_managed_zone.default.dns_name}"
  ttl          = 300
  type         = "A"
  managed_zone = google_dns_managed_zone.default.name
  rrdatas = [google_compute_address.smallstep_address.address]
}

resource "google_dns_record_set" "web_auth" {
  project      = var.project_id
  name         = "auth.${google_dns_managed_zone.default.dns_name}"
  ttl          = 300
  type         = "A"
  managed_zone = google_dns_managed_zone.default.name
  rrdatas = [google_compute_address.smallstep_address.address]
}

resource "google_dns_record_set" "web_api_scim" {
  project      = var.project_id
  name         = "scim.api.${google_dns_managed_zone.default.dns_name}"
  ttl          = 300
  type         = "A"
  managed_zone = google_dns_managed_zone.default.name
  rrdatas = [google_compute_address.smallstep_address.address]
}

resource "google_dns_record_set" "web_api_gateway" {
  project      = var.project_id
  name         = "gateway.api.${google_dns_managed_zone.default.dns_name}"
  ttl          = 300
  type         = "A"
  managed_zone = google_dns_managed_zone.default.name
  rrdatas = [google_compute_address.smallstep_address.address]
}

resource "google_dns_record_set" "web_app" {
  project      = var.project_id
  name         = "app.${google_dns_managed_zone.default.dns_name}"
  ttl          = 300
  type         = "A"
  managed_zone = google_dns_managed_zone.default.name
  rrdatas = [google_compute_address.smallstep_address.address]
}

resource "google_dns_record_set" "landlord_teams" {
  project      = var.project_id
  name         = "*.ca.${google_dns_managed_zone.default.dns_name}"
  ttl          = 300
  type         = "A"
  managed_zone = google_dns_managed_zone.default.name
  rrdatas = [google_compute_address.smallstep_address.address]
}

resource "google_dns_record_set" "magpie_teams" {
  project      = var.project_id
  name         = "*.logs.${google_dns_managed_zone.default.dns_name}"
  ttl          = 300
  type         = "A"
  managed_zone = google_dns_managed_zone.default.name
  rrdatas      = [google_compute_address.smallstep_address.address]
}

resource "google_dns_record_set" "tunnel" {
  project      = var.project_id
  name         = "tunnel.${google_dns_managed_zone.default.dns_name}"
  ttl          = 300
  type         = "A"
  managed_zone = google_dns_managed_zone.default.name
  rrdatas      = [google_compute_address.smallstep_address.address]
}

output "zone" {
  value = google_dns_managed_zone.default.dns_name
}

output "name_servers" {
  value = google_dns_managed_zone.default.name_servers
}

output "base_domain" {
  value = trimsuffix(google_dns_managed_zone.default.dns_name, ".")
}

output "api_domain" {
  value = trimsuffix(google_dns_record_set.web_api.name, ".")
}

output "gateway_domain" {
  value = trimsuffix(google_dns_record_set.web_api_gateway.name, ".")
}

output "scim_domain" {
  value = trimsuffix(google_dns_record_set.web_api_scim.name, ".")
}
