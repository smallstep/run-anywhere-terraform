
resource "azurerm_kubernetes_cluster" "primary" {
  name                      = var.k8s_cluster_name
  location                  = azurerm_resource_group.smallstep.location
  resource_group_name       = azurerm_resource_group.smallstep.name
  automatic_channel_upgrade = "stable"
  dns_prefix                = var.k8s_cluster_name

  default_node_pool {
    name            = "default"
    node_count      = 3
    vm_size         = "Standard_D2_v2"
    os_disk_size_gb = 30
    vnet_subnet_id           = azurerm_subnet.default.id
  }

  network_profile {
    network_plugin = "kubenet"

    load_balancer_sku = "standard"

    load_balancer_profile {
      outbound_ip_address_ids = [azurerm_public_ip.smallstep_address.id]
    }
  }

  identity {
    type = "SystemAssigned"
  }
}

output "kubelet_client_id" {
  value = azurerm_kubernetes_cluster.primary.kubelet_identity[0].client_id
}

output "role_scope" {
  value = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_kubernetes_cluster.primary.node_resource_group}"
}

resource "azurerm_role_assignment" "agentpool_msi2" {
  scope                            = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_kubernetes_cluster.primary.node_resource_group}"
  role_definition_name             = "Managed Identity Operator"
  # TODO not clientID? https://raw.githubusercontent.com/Azure/aad-pod-identity/v1.8.9/deploy/infra/deployment-rbac.yaml
  principal_id = azurerm_kubernetes_cluster.primary.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "agentpool_vm2" {
  scope                            = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_kubernetes_cluster.primary.node_resource_group}"
  role_definition_name             = "Virtual Machine Contributor"
  principal_id = azurerm_kubernetes_cluster.primary.kubelet_identity[0].object_id
  # principal_id                     = data.azurerm_user_assigned_identity.agentpool.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "agentpool_msi" {
  scope                            = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_kubernetes_cluster.primary.node_resource_group}"
  role_definition_name             = "Managed Identity Operator"
  # TODO not clientID? https://raw.githubusercontent.com/Azure/aad-pod-identity/v1.8.9/deploy/infra/deployment-rbac.yaml
  principal_id = azurerm_kubernetes_cluster.primary.kubelet_identity[0].client_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "agentpool_vm" {
  scope                            = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${azurerm_kubernetes_cluster.primary.node_resource_group}"
  role_definition_name             = "Virtual Machine Contributor"
  principal_id = azurerm_kubernetes_cluster.primary.kubelet_identity[0].client_id
  # principal_id                     = data.azurerm_user_assigned_identity.agentpool.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "agentpool_networking" {
  scope                            = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourcegroups/${azurerm_resource_group.smallstep.name}"
  # scope                            = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourcegroups/${azurerm_kubernetes_cluster.primary.node_resource_group}"
  # scope                            = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourcegroups/"
  role_definition_name             = "Network Contributor"
  principal_id = azurerm_kubernetes_cluster.primary.identity[0].principal_id
  # principal_id = azurerm_kubernetes_cluster.primary.kubelet_identity[0].object_id
  # principal_id                     = data.azurerm_user_assigned_identity.agentpool.principal_id
  skip_service_principal_aad_check = true
}

# helm chart for the aad pod identity
resource "helm_release" "aad_pod_identity" {
  name       = "aad-pod-identity"
  repository = "https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts"
  chart      = "aad-pod-identity"
  namespace  = "kube-system"
  version    = "4.1.10"
}

resource "kubernetes_manifest" "azure_identity" {
  depends_on = [helm_release.aad_pod_identity]
  manifest = {
    "apiVersion" = "aadpodidentity.k8s.io/v1"
    "kind" = "AzureIdentity"
    "metadata" = {
      "name": "landlord"
      "namespace": "smallstep"
    }
    "spec" = {
      # "type" = "UserAssignedMSI"
      "clientID" = "${azurerm_kubernetes_cluster.primary.kubelet_identity[0].client_id}"
      "resourceID" = "/subscriptions/f0ef333d-357c-45f7-afba-a8f66b952022/resourcegroups/MC_onprem_smallstep_centralus/providers/Microsoft.ManagedIdentity/userAssignedIdentities/smallstep-agentpool"
      #"resourceID" = "${azurerm_kubernetes_cluster.primary.kubelet_identity[0].object_id}"
      # "clientID" = "${azurerm_user_assigned_identity.aks01_kv.client_id}"
      # "resourceID" = "${azurerm_user_assigned_identity.aks01_kv.id}"
    }
  }
}

resource "kubernetes_manifest" "azure_identity_binding" {
  depends_on = [helm_release.aad_pod_identity]

  manifest = {
    "apiVersion" = "aadpodidentity.k8s.io/v1"
    "kind" = "AzureIdentityBinding"

    "metadata" = {
      "name" = "landlord"
      "namespace" = "smallstep"
    }

    "spec" = {
      "azureIdentity" =  "landlord"
      "selector" = "landlord"
    }
  }
}