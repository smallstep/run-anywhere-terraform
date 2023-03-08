#-------------------------------------------------------------------------------------- 
# 
# This file hosts all networking resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

data "google_compute_network" "default" {
  project    = var.project_id
  depends_on = [google_project_service.compute]
  name       = "default"
}

resource "google_compute_firewall" "allow_ssh" {
  project = var.project_id
  network = data.google_compute_network.default.name
  name    = "${var.name}-allow-ssh"
  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_http" {
  project = var.project_id
  network = data.google_compute_network.default.name
  name    = "${var.name}-allow-http"
  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_tls" {
  project = var.project_id
  network = data.google_compute_network.default.name
  name    = "${var.name}-allow-tls"
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_address" "smallstep_address" {
  project     = var.project_id
  region      = var.region
  name        = "${var.name}-smallstep-address"
  description = "smallstep proxy load balancer"
  depends_on  = [google_project_service.compute]
}

resource "google_compute_global_address" "service_allocation" {
  project       = var.project_id
  network       = data.google_compute_network.default.name
  name          = "${var.name}-service-allocation"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
}

resource "google_service_networking_connection" "servicenetworking" {
  count = var.managed_servicenetworking == true ? 1 : 0

  network                 = data.google_compute_network.default.self_link
  depends_on              = [google_project_service.servicenetworking]
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.service_allocation.name]
}