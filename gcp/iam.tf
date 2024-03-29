#-------------------------------------------------------------------------------------- 
# 
# This file hosts all IAM resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

resource "google_service_account" "landlord" {
  project      = var.project_id
  account_id   = "landlord"
  display_name = "landlord"
  depends_on   = [google_project_service.gke]
}

resource "google_service_account_iam_binding" "landlord_workload_identity" {
  service_account_id = google_service_account.landlord.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/landlord]",
  ]
  depends_on = [google_container_cluster.primary]
}

resource "google_project_iam_member" "landlord_kms_admin" {
  project = var.project_id
  role    = "roles/cloudkms.admin"
  member  = "serviceAccount:${google_service_account.landlord.email}"
}

resource "google_project_iam_member" "landlord_kms_pubkey_viewer" {
  project = var.project_id
  role    = "roles/cloudkms.publicKeyViewer"
  member  = "serviceAccount:${google_service_account.landlord.email}"
}

resource "google_project_iam_member" "landlord_kms_signer" {
  project = var.project_id
  role    = "roles/cloudkms.signer"
  member  = "serviceAccount:${google_service_account.landlord.email}"
}

resource "google_project_iam_member" "landlord_kms_verifier" {
  project = var.project_id
  role    = "roles/cloudkms.signerVerifier"
  member  = "serviceAccount:${google_service_account.landlord.email}"
}

// web-api workload identity and roles
resource "google_service_account" "web_api" {
  project      = var.project_id
  account_id   = "web-api"
  display_name = "web-api"
}

resource "google_service_account_iam_binding" "web_api_workload_identity" {
  service_account_id = google_service_account.web_api.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/web-api]",
  ]
  depends_on = [google_container_cluster.primary]
}

// web-frontend workload identity and roles
resource "google_service_account" "web_frontend" {
  project      = var.project_id
  account_id   = "web-frontend"
  display_name = "web-frontend"
  depends_on   = [google_project_service.gke]
}

resource "google_service_account_iam_binding" "web_frontend_workload_identity" {
  service_account_id = google_service_account.web_frontend.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/web-frontend]",
  ]
  depends_on = [google_container_cluster.primary]
}

// SCIM Server - GSuite service account
//
// This service account MUST NOT change, if it does a new service account will
// be created. ClientIDs will be distributed to customers and they MUST remain
// fixed.
resource "google_service_account" "scim_server" {
  project      = var.project_id
  account_id   = "scim-server"
  display_name = "scim-server"
  depends_on   = [google_project_service.gke]
}

resource "google_service_account_iam_binding" "scim_server_workload_identity" {
  service_account_id = google_service_account.scim_server.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/scim-server]",
  ]
  depends_on = [google_container_cluster.primary]
}

resource "google_service_account_key" "scim_server_key" {
  service_account_id = google_service_account.scim_server.name
}

// Majordomo workload identity and roles
resource "google_service_account" "majordomo" {
  project      = var.project_id
  account_id   = "majordomo"
  display_name = "majordomo"
  depends_on   = [google_project_service.gke]
}

resource "google_project_iam_member" "majordomo_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.majordomo.email}"
}

resource "google_service_account_iam_binding" "majordomo_workload_identity" {
  service_account_id = google_service_account.majordomo.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/majordomo]",
  ]
  depends_on = [google_container_cluster.primary]
}

// Moody workload identity and roles
resource "google_service_account" "moody" {
  project = var.project_id
  // 'moody' is too short to pass validation rules, hence 'moody-acc'
  account_id   = "moody-acc"
  display_name = "moody-acc"
  depends_on   = [google_project_service.gke]
}

resource "google_project_iam_member" "moody_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.moody.email}"
}

resource "google_service_account_iam_binding" "moody_workload_identity" {
  service_account_id = google_service_account.moody.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/moody-acc]",
  ]
  depends_on = [google_container_cluster.primary]
}

// Magpie workload identity and roles
resource "google_service_account" "magpie" {
  project      = var.project_id
  account_id   = "magpie"
  display_name = "magpie"
  depends_on   = [google_project_service.gke]
}

resource "google_service_account_iam_binding" "magpie_workload_identity" {
  service_account_id = google_service_account.magpie.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/magpie]",
  ]
  depends_on = [google_container_cluster.primary]
}

resource "google_project_iam_member" "magpie_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.magpie.email}"
}

resource "google_service_account_key" "magpie" {
  service_account_id = google_service_account.magpie.name
}

// Veto workload identity and roles

resource "google_service_account" "veto" {
  project      = var.project_id
  account_id   = "veto-acc"
  display_name = "veto-acc"
  depends_on   = [google_project_service.gke]
}

resource "google_service_account_iam_binding" "veto_workload_identity" {
  service_account_id = google_service_account.veto.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/veto-acc]",
  ]
  depends_on = [google_container_cluster.primary]
}

resource "google_storage_bucket_iam_binding" "veto" {
  bucket = google_storage_bucket.veto_crls.name
  role   = "roles/storage.objectAdmin"
  members = [
    "serviceAccount:${google_service_account.veto.email}",
  ]
}

resource "google_service_account_key" "veto" {
  service_account_id = google_service_account.veto.name
}

// Approvalq workload identity and roles
resource "google_service_account" "approvalq" {
  project      = var.project_id
  account_id   = "approvalq"
  display_name = "approvalq"
  depends_on   = [google_project_service.gke]
}

resource "google_service_account_iam_binding" "approvalq_workload_identity" {
  service_account_id = google_service_account.approvalq.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/approvalq]",
  ]
  depends_on = [google_container_cluster.primary]
}


resource "google_project_iam_member" "approvalq_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.approvalq.email}"
}

resource "google_service_account_key" "approvalq" {
  service_account_id = google_service_account.approvalq.name
}

resource "google_service_account" "inventory" {
  project      = var.project_id
  account_id   = "inventory"
  display_name = "inventory"
}

resource "google_service_account_iam_binding" "inventory_workload_identity" {
  service_account_id = google_service_account.inventory.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/inventory]",
  ]
  depends_on = [google_container_cluster.primary]
}

resource "google_service_account" "missioncontrol" {
  project      = var.project_id
  account_id   = "mission-control"
  display_name = "mission-control"
}

resource "google_service_account_iam_binding" "missioncontrol_workload_identity" {
  service_account_id = google_service_account.missioncontrol.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/mission-control]",
  ]
  depends_on = [google_container_cluster.primary]
}

// Mission control verifies tokens issued by Gateway API
resource "google_project_iam_member" "mission_control_kms_pubkey_viewer" {
  project = var.project_id
  role    = "roles/cloudkms.publicKeyViewer"
  member  = "serviceAccount:${google_service_account.missioncontrol.email}"
}

resource "google_service_account" "guardian" {
  project      = var.project_id
  account_id   = "guardian"
  display_name = "guardian"
}

resource "google_service_account_iam_binding" "guardian_workload_identity" {
  service_account_id = google_service_account.guardian.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/guardian]",
  ]
  depends_on = [google_container_cluster.primary]
}

resource "google_project_iam_member" "guardian_kms_admin" {
  project = var.project_id
  role    = "roles/cloudkms.admin"
  member  = "serviceAccount:${google_service_account.guardian.email}"
}

resource "google_project_iam_member" "guardian_kms_pubkey_viewer" {
  project = var.project_id
  role    = "roles/cloudkms.publicKeyViewer"
  member  = "serviceAccount:${google_service_account.guardian.email}"
}

resource "google_project_iam_member" "guardian_kms_signer" {
  project = var.project_id
  role    = "roles/cloudkms.signer"
  member  = "serviceAccount:${google_service_account.guardian.email}"
}

resource "google_project_iam_member" "guardian_kms_verifier" {
  project = var.project_id
  role    = "roles/cloudkms.signerVerifier"
  member  = "serviceAccount:${google_service_account.guardian.email}"
}

resource "google_service_account" "gateway" {
  project      = var.project_id
  account_id   = "gateway"
  display_name = "gateway"
}

resource "google_service_account_iam_binding" "gateway_workload_identity" {
  service_account_id = google_service_account.gateway.name
  role               = "roles/iam.workloadIdentityUser"
  members = [
    "serviceAccount:${var.project_id}.svc.id.goog[${var.namespace}/gateway]",
  ]
  depends_on = [google_container_cluster.primary]
}

resource "google_project_iam_member" "gateway_kms_signer" {
  project = var.project_id
  role    = "roles/cloudkms.signer"
  member  = "serviceAccount:${google_service_account.gateway.email}"
}

resource "google_project_iam_member" "gateway_kms_verifier" {
  project = var.project_id
  role    = "roles/cloudkms.signerVerifier"
  member  = "serviceAccount:${google_service_account.gateway.email}"
}
