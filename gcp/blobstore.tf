# A public bucket to store CRLs
resource "google_storage_bucket" "veto_crlS" {
  project = var.project_id
  name    = "crl.${google_dns_managed_zone.default.dns_name}"
}

resource "google_storage_default_object_access_control" "veto_public_acl" {
  bucket = google_storage_bucket.veto_crls.name
  role   = "READER"
  entity = "allUsers"
}
