# Created directly (instead of via the ai_foundry module's built-in BYOR
# path) so it can run in Serverless mode. The AVM module doesn't currently
# wire a `capabilities`/serverless option through, and Standard Agent Setup's
# provisioned-throughput floor (>=3000 RU/s) would otherwise cost real money
# if left running. Serverless is pay-per-request with no minimum.
#
# The name/id are derived only from static inputs (not from another
# resource's computed output) so the ID can be passed to the ai_foundry
# module's `existing_resource_id` and be known at plan time, even on a
# first-ever apply before this account exists yet. Using
# azurerm_cosmosdb_account.this.id there instead would be unknown at plan
# time and break the module's for_each.
locals {
  cosmosdb_name = "cosmos-${var.base_name}-${substr(sha1("${var.resource_group_name}-${var.base_name}-cosmos"), 0, 8)}"
  cosmosdb_id   = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${data.azurerm_resource_group.this.name}/providers/Microsoft.DocumentDB/databaseAccounts/${local.cosmosdb_name}"
}

resource "azurerm_cosmosdb_account" "this" {
  name                = local.cosmosdb_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  public_network_access_enabled = false
  local_authentication_enabled  = false

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }
}

resource "azurerm_private_endpoint" "cosmosdb" {
  name                = "pe-${azurerm_cosmosdb_account.this.name}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-${azurerm_cosmosdb_account.this.name}"
    private_connection_resource_id = azurerm_cosmosdb_account.this.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.this["privatelink.documents.azure.com"].id]
  }
}
