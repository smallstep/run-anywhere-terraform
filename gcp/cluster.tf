#-------------------------------------------------------------------------------------- 
# 
# This file hosts all K8s Cluster resources for the GCP Run Anywhere deployment.
# 
#--------------------------------------------------------------------------------------

resource "google_container_cluster" "primary" {
  provider = google-beta
  project  = var.project_id

  name     = var.k8s_cluster_name
  location = var.region

  release_channel {
    channel = var.k8s_channel
  }

  network = data.google_compute_network.default.name
  ip_allocation_policy {}
  enable_intranode_visibility = true

  master_auth {
    # Disable basic auth
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }
  workload_identity_config {
    identity_namespace = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing {
      disabled = false
    }
    istio_config {
      disabled = true
      auth     = "AUTH_MUTUAL_TLS"
    }
  }

  cluster_autoscaling {
    enabled = false
  }

  # We want to use the node pool resource declared below.
  remove_default_node_pool = true
  initial_node_count       = 1

  depends_on  = [google_project_service.compute, google_project_service.gke]
}

resource "google_container_node_pool" "primary" {
  provider = google-beta
  project  = var.project_id

  name     = "smallstep"
  location = var.region
  cluster  = google_container_cluster.primary.name

  node_config {
    machine_type = var.node_machine_type

    metadata = {
      disable-legacy-endpoints = "true"
    }
    oauth_scopes = [
      "https://www.googleapis.com/auth/devstorage.read_only",
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]
    workload_metadata_config {
      node_metadata = "GKE_METADATA_SERVER"
    }
  }
  node_count = var.node_count
  management {
    auto_repair  = var.node_auto_repair
    auto_upgrade = var.node_auto_upgrade
  }
  upgrade_settings {
    max_surge       = var.node_max_surge_count
    max_unavailable = var.node_max_unavailable

  }
}
