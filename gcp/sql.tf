#-------------------------------------------------------------------------------------- 
# 
# This file hosts all CloudSQL resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

resource "google_sql_database_instance" "master" {
  name             = "smallstep"
  project          = var.project_id
  database_version = "POSTGRES_11"
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
      "cluster_name"  = "smallstep"
      "instance_name" = "smallstep-primary"
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

// decrypt postgresql password

data "google_kms_secret" "postgresql_password" {
  crypto_key = data.google_kms_crypto_key.terraform_secret.self_link
  ciphertext = filebase64("secrets/postgresql_password.enc")
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

resource "google_sql_user" "postgres" {
  project  = var.project_id
  name     = "postgres"
  instance = google_sql_database_instance.master.name
  password = data.google_kms_secret.postgresql_password.plaintext
}

output "sql_master_host" {
  value = google_sql_database_instance.master.private_ip_address
}

output "sql_master_host_public" {
  value = google_sql_database_instance.master.public_ip_address
}

output "sql_db_depot" {
  value = google_sql_database.depot.name
}

output "sql_db_folk" {
  value = google_sql_database.folk.name
}

output "sql_db_memoir" {
  value = google_sql_database.memoir.name
}

output "sql_db_courier" {
  value = google_sql_database.courier.name
}

output "sql_db_web_user" {
  value = google_sql_user.postgres.name
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
  ])
}

output "db_names" {
  value = local.db_names
}