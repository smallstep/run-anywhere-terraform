resource "azurerm_user_assigned_identity" "smallstep" {
  location            = azurerm_resource_group.smallstep.location
  name                = "smallstep"
  resource_group_name = azurerm_resource_group.smallstep.name
}

resource "azurerm_kubernetes_cluster" "primary" {
  name                      = var.k8s_cluster_name
  location                  = azurerm_resource_group.smallstep.location
  resource_group_name       = azurerm_resource_group.smallstep.name
  automatic_channel_upgrade = "stable"
  dns_prefix                = var.k8s_cluster_name
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name            = "default"
    node_count      = 3
    vm_size         = "Standard_D2_v2"
    os_disk_size_gb = 30
    vnet_subnet_id  = azurerm_subnet.default.id
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

resource "azurerm_role_assignment" "agentpool_networking" {
  scope                            = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourcegroups/${azurerm_resource_group.smallstep.name}"
  role_definition_name             = "Network Contributor"
  principal_id                     = azurerm_kubernetes_cluster.primary.identity[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "smallstep_crypto_officer" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourcegroups/${azurerm_resource_group.smallstep.name}"
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = azurerm_user_assigned_identity.smallstep.principal_id
}

resource "azurerm_role_assignment" "smallstep_storage_blob_data_contributor" {
  scope                = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourcegroups/${azurerm_resource_group.smallstep.name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.smallstep.principal_id
}

resource "azurerm_federated_identity_credential" "smallstep-landlord" {
  name                = "smallstep-landlord"
  resource_group_name = azurerm_resource_group.smallstep.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.primary.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.smallstep.id
  subject             = "system:serviceaccount:${var.namespace}:landlord"
}

resource "azurerm_federated_identity_credential" "smallstep-veto" {
  name                = "smallstep-veto"
  resource_group_name = azurerm_resource_group.smallstep.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.primary.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.smallstep.id
  subject             = "system:serviceaccount:${var.namespace}:veto-acc"
}

resource "azurerm_federated_identity_credential" "smallstep-gateway" {
  name                = "smallstep-gateway"
  resource_group_name = azurerm_resource_group.smallstep.name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.primary.oidc_issuer_url
  parent_id           = azurerm_user_assigned_identity.smallstep.id
  subject             = "system:serviceaccount:${var.namespace}:gateway"
}

