resource "google_kms_key_ring" "gateway" {
  project = var.project_id
  name     = "gateway"
  location = "global"
}

resource "google_kms_crypto_key" "gateway_jwt_signing_key" {
  name     = "gateway-jwt-signing-key"
  key_ring = google_kms_key_ring.gateway.id
  purpose  = "ASYMMETRIC_SIGN"

  version_template {
    algorithm = "EC_SIGN_P256_SHA256"
  }
}
