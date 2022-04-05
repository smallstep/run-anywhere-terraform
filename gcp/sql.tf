#-------------------------------------------------------------------------------------- 
# 
# This file hosts all CloudSQL resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

// decrypt postgresql password
data "google_kms_secret" "postgresql_password" {
  crypto_key = data.google_kms_crypto_key.terraform_secret.self_link
  ciphertext = filebase64("${var.path_to_secrets}/postgresql_password.enc")
}

locals {
  kube_ctx = "gke_${var.project_id}_${google_container_cluster.primary.location}_${google_container_cluster.primary.name}"
  db_names = join(" ", [
    google_sql_database.landlord.name,
    google_sql_database.certificates.name,
    google_sql_database.web.name,
    google_sql_database.depot.name,
    google_sql_database.folk.name,
    google_sql_database.memoir.name,
    google_sql_database.courier.name,
    google_sql_database.majordomo.name,
    google_sql_database.moody.name,
    google_sql_database.veto.name,
    google_sql_database.approvalq.name,
  ])
}

resource "google_sql_database_instance" "master" {
  name             = var.db_name
  project          = var.project_id
  database_version = var.sql_database_version
  region           = var.region
  depends_on       = [google_service_networking_connection.servicenetworking]
  settings {
    tier = var.cloudsql_instance_tier
    backup_configuration {
      enabled  = true
      location = "us"
    }
    ip_configuration {
      ipv4_enabled = var.cloudsql_enable_public_ip
      authorized_networks {
        name  = "all-v4"
        value = "0.0.0.0/0"
      }
      private_network = data.google_compute_network.default.self_link
    }
    insights_config {
      query_insights_enabled  = true
      query_string_length     = 1024
      record_application_tags = true
      record_client_address   = true
    }
    availability_type = var.cloudsql_high_availability ? "REGIONAL" : "ZONAL"
    user_labels = {
      "cluster_name"  = var.db_name
      "instance_name" = "${var.db_name}-primary"
    }
    database_flags {
      name  = "log_min_duration_statement"
      value = var.cloudsql_log_min_duration_statement
    }
    database_flags {
      name  = "work_mem"
      value = var.cloudsql_work_mem
    }
  }
}

resource "google_sql_database" "landlord" {
  project  = var.project_id
  name     = "landlord"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "certificates" {
  project  = var.project_id
  name     = "certificates"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "web" {
  project  = var.project_id
  name     = "web"
  instance = google_sql_database_instance.master.name
}

// databases for new microservices stack
resource "google_sql_database" "depot" {
  project  = var.project_id
  name     = "depot"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "folk" {
  project  = var.project_id
  name     = "folk"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "memoir" {
  project  = var.project_id
  name     = "memoir"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "majordomo" {
  project  = var.project_id
  name     = "majordomo"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "moody" {
  project  = var.project_id
  name     = "moody"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "courier" {
  project  = var.project_id
  name     = "courier"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "veto" {
  project  = var.project_id
  name     = "veto"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "approvalq" {
  project  = var.project_id
  name     = "approvalq"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_user" "postgres" {
  project  = var.project_id
  name     = "postgres"
  instance = google_sql_database_instance.master.name
  password = data.google_kms_secret.postgresql_password.plaintext
}