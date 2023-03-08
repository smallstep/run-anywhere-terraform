#-------------------------------------------------------------------------------------- 
# 
# This file hosts all Redis resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

resource "google_redis_instance" "smallstep" {
  project            = var.project_id
  depends_on         = [google_project_service.redis]
  region             = var.region
  redis_version      = var.redis_version
  tier               = var.redis_tier
  name               = "${var.name}"
  memory_size_gb     = var.redis_memory_size_gb
  authorized_network = data.google_compute_network.default.self_link
}