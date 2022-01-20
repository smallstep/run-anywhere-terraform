terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 3.58.0"
    }

    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 3.58.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.1"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.6"
    }
  }
}

provider "google" {
  region = var.region
  zone   = var.zone
}

provider "google-beta" {
  region = var.region
  zone   = var.zone
}

provider "kubernetes" {
  host                   = google_container_cluster.primary.endpoint
  username               = google_container_cluster.primary.master_auth[0].username
  password               = google_container_cluster.primary.master_auth[0].password
  client_certificate     = base64decode(google_container_cluster.primary.master_auth[0].client_certificate)
  client_key             = base64decode(google_container_cluster.primary.master_auth[0].client_key)
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  config_path            = var.kube_config_path
}