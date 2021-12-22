#-------------------------------------------------------------------------------------- 
# 
# This file hosts all Redis resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

resource "google_redis_instance" "smallstep" {
  project            = var.project_id
  depends_on         = [google_project_service.redis]
  region             = var.region
  redis_version      = "REDIS_4_0"
  tier               = "BASIC"
  name               = "smallstep"
  memory_size_gb     = 1
  authorized_network = data.google_compute_network.default.self_link
}

output "redis_host" {
  value = google_redis_instance.smallstep.host
}

output "redis_port" {
  value = google_redis_instance.smallstep.port
}

output "redis_addr" {
  value = "${google_redis_instance.smallstep.host}:${google_redis_instance.smallstep.port}"
}
