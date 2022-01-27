#-------------------------------------------------------------------------------------- 
# 
# This file hosts all project-related resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

data "google_client_config" "current" {}

data "google_compute_default_service_account" "default" {
  project    = var.project_id
  depends_on = [google_project_service.compute]
}

// The keys used to encrypt project configuration secrets can't themselves
// be project resources.
data "google_kms_key_ring" "keys" {
  project  = var.project_id
  location = "global"
  name     = "smallstep-terraform"
}

// This is the secret used to decrypt encrypted secrets in this repo
data "google_kms_crypto_key" "terraform_secret" {
  key_ring = data.google_kms_key_ring.keys.self_link
  name     = "terraform-secret"
}

resource "google_project_service" "compute" {
  project = var.project_id
  service = "compute.googleapis.com"
}

resource "google_project_service" "storage-component" {
  project = var.project_id
  service = "storage-component.googleapis.com"
}

resource "google_project_service" "storage-json-api" {
  project = var.project_id
  service = "storage-api.googleapis.com"
}

resource "google_project_service" "cloudscheduler" {
  project = var.project_id
  service = "cloudscheduler.googleapis.com"
}

resource "google_project_service" "cloudresourcemanager" {
  project = var.project_id
  service = "cloudresourcemanager.googleapis.com"
}

resource "google_project_service" "appengine" {
  project = var.project_id
  service = "appengine.googleapis.com"
}

resource "google_project_service" "dns" {
  project = var.project_id
  service = "dns.googleapis.com"
}

resource "google_project_service" "servicenetworking" {
  project = var.project_id
  service = "servicenetworking.googleapis.com"
}

resource "google_project_service" "gke" {
  project    = var.project_id
  service    = "container.googleapis.com"
  depends_on = [google_project_service.compute]
}

resource "google_project_service" "redis" {
  project = var.project_id
  service = "redis.googleapis.com"
  depends_on = [
    google_project_service.gke,
    google_project_service.resourceviews
  ]
}

resource "google_project_service" "cloudkms" {
  project = var.project_id
  service = "cloudkms.googleapis.com"
}

resource "google_project_service" "resourceviews" {
  project    = var.project_id
  service    = "resourceviews.googleapis.com"
  depends_on = [google_project_service.gke]
}

resource "google_project_service" "admin" {
  project = var.project_id
  service = "admin.googleapis.com"
}

resource "google_project_service" "cloudsqladmin" {
  project = var.project_id
  service = "sqladmin.googleapis.com"
}