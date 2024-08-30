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

data "google_kms_secret" "postgresql_cas_replication_user_password" {
  crypto_key = data.google_kms_crypto_key.terraform_secret.self_link
  ciphertext = filebase64("${var.path_to_secrets}/postgresql_cas_replication_user_password.enc")
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
    google_sql_database.inventory.name,
    google_sql_database.guardian.name,
    google_sql_database.mission_control.name,
    google_sql_database.gateway.name,
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

resource "google_sql_database" "inventory" {
  project  = var.project_id
  name     = "inventory"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "guardian" {
  project  = var.project_id
  name     = "guardian"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "mission_control" {
  project  = var.project_id
  name     = "mission_control"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_database" "gateway" {
  project  = var.project_id
  name     = "gateway"
  instance = google_sql_database_instance.master.name
}

resource "google_sql_user" "postgres" {
  project  = var.project_id
  name     = "postgres"
  instance = google_sql_database_instance.master.name
  password = data.google_kms_secret.postgresql_password.plaintext
}

resource "null_resource" "sql_db_landlord_replication_log_user" {
  depends_on = [
    google_project_service.cloudsqladmin
  ]

  // NOTE: If you've gotten an error because you are trying to update this
  // resource, but Terraform needs to destroy the resource in order to update,
  // follow these steps:
  //
  // 1) Comment out the "lifecycle" block below this comment.
  // 2) Comment out the "on destroy" provisioner at the bottom of this resource.
  // 3) Along with your existing changes meant to update this resource,
  //    `terraform apply` your changes.
  // 4) Uncomment the "lifecycle" and "on destroy" blocks and `terraform apply`.
  // 5) Commit and push your changes.
  //
  // The lifecycle "prevent_destroy" block is here to make certain we do not
  // unintentionally destroy this resource (and automaticallyrun the "on
  // destroy" script) when we are actually trying to update the resource.
  lifecycle {
    prevent_destroy = true
  }

  triggers = {
    // if this needs to be executed on every run, use this trigger:
    // build_number = "${timestamp()}"

    // triggers based on mutable inputs to this resource
    // script runs as the postgres user, but destroy target can't access variables outside of the resource,
    // so we pass this to the script and manually decrypt it.
    PGPASSWORD_ciphertext = data.google_kms_secret.postgresql_password.ciphertext
    project = var.project_id
    db_instance           = google_sql_database_instance.master.id
    db_connection_name    = google_sql_database_instance.master.connection_name
    user                  = "landlordcachesrv"
    // force update when the password changes
    user_pw_ciphertext    = data.google_kms_secret.postgresql_cas_replication_user_password.ciphertext
    // this should force re-execution of this resource when the grants change
    user_grants           = file("./sql/create_replication_log_user.sql")
    kube_ctx              = local.kube_ctx
    db_names              = join(" ", [
      google_sql_database.landlord.name,
    ])
  }

  provisioner "local-exec" {
    command = "./sql/manage_user.sh"
    environment = {
      ACTION    = "create"
      PROJECT   = self.triggers.project
      KUBE_CTX  = self.triggers.kube_ctx
      // sql script runs as the postgres user, psql looks for a password in $PGPASSWORD
      PGPASSWORD      = google_sql_user.postgres.password
      DB_INSTANCE     = self.triggers.db_connection_name
      USER            = self.triggers.user
      PW              = data.google_kms_secret.postgresql_cas_replication_user_password.plaintext
      DB_NAMES        = self.triggers.db_names
      CREATE_USER_SQL = "sql/create_replication_log_user.sql"
      PORT            = 5434
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "./sql/manage_user.sh"
    environment = {
      ACTION    = "destroy"
      PROJECT   = self.triggers.project
      KUBE_CTX  = self.triggers.kube_ctx
      // sql script runs as the postgres user, ciphertext is passed to script which attempts to decrypt and set PGPASSWORD.
      // terraform does not allow accessing variables outside of the resource for destroy provisioners
      PGPASSWORD_ciphertext  = self.triggers.PGPASSWORD_ciphertext
      DB_INSTANCE            = self.triggers.db_connection_name
      USER                   = self.triggers.user
      DB_NAMES               = self.triggers.db_names
      REVOKE_USER_GRANTS_SQL = "sql/revoke_replication_log_user_grants.sql"
      DROP_USER_SQL          = "sql/drop_replication_log_user.sql"
      PORT                   = 5434
    }
  }
}
