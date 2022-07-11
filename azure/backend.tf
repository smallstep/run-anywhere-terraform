terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.10"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.11"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.6"
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "smallstep" {
  name     = var.resource_group_name
  location = var.resource_group_location
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.primary.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.primary.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.primary.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.primary.kube_config.0.cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.primary.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.primary.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.primary.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.primary.kube_config.0.cluster_ca_certificate)
  }
}
