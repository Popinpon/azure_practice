# Azure AI Foundry account + Standard Agent Setup.
# - Inbound: public endpoint is enabled but restricted to admin_source_cidr
#   via network_acls, so it can be called directly from your machine without
#   a jump box. A private endpoint is also kept (create_private_endpoints =
#   true) for the agent runtime's own access to the account.
# - Outbound (the actual point of this exercise): create_ai_agent_service +
#   network_injections places the agent runtime in snet-agent, which has no
#   default outbound access and is forced through nat_gateway.tf's NAT
#   Gateway. All calls the agent makes to external MCP servers therefore
#   originate from that NAT Gateway's static public IP.
data "azurerm_client_config" "current" {}

locals {
  ai_foundry_name = "aif-${var.base_name}-${random_string.suffix.result}"
}

module "ai_foundry" {
  source  = "Azure/avm-ptn-aiml-ai-foundry/azurerm"
  version = "0.11.3"

  base_name                           = var.base_name
  location                            = var.location
  resource_group_resource_id          = data.azurerm_resource_group.this.id
  private_endpoint_subnet_resource_id = azurerm_subnet.private_endpoints.id

  create_private_endpoints = true
  create_byor              = true

  ai_foundry = {
    name                    = local.ai_foundry_name
    create_ai_agent_service = true
    network_injections = [{
      scenario                   = "agent"
      subnetArmId                = azurerm_subnet.agent.id
      useMicrosoftManagedNetwork = false
    }]
    private_dns_zone_resource_ids = [
      for name in local.ai_foundry_dns_zone_names : azurerm_private_dns_zone.this[name].id
    ]
    # Public endpoint enabled but locked to admin_source_cidr, so it can be
    # called directly (no jump box needed) while still blocking everyone else.
    public_network_access_enabled = true
    network_acls = {
      default_action = "Deny"
      ip_rules       = [var.admin_source_cidr]
    }
  }

  ai_model_deployments = {
    default = {
      name = var.model_name
      model = {
        format  = "OpenAI"
        name    = var.model_name
        version = var.model_version
      }
      scale = {
        type     = "GlobalStandard"
        capacity = var.model_capacity
      }
    }
  }

  ai_projects = {
    project_1 = {
      name                       = "${var.base_name}-project"
      display_name               = "Closed Foundry Project"
      description                = "Project used to test fixed-egress-IP MCP access from the AI Foundry agent."
      create_project_connections = true
      cosmos_db_connection       = { existing_resource_id = local.cosmosdb_id }
      ai_search_connection       = { new_resource_map_key = "this" }
      storage_account_connection = { new_resource_map_key = "this" }
    }
  }

  # sku/replica_count overridden from the module defaults (standard x2
  # replicas ~= $500/mo) down to the cheapest tier that still supports
  # private endpoints, since this is a throwaway test deployment.
  ai_search_definition = {
    this = {
      private_dns_zone_resource_id = azurerm_private_dns_zone.this["privatelink.search.windows.net"].id
      sku                          = "basic"
      replica_count                = 1
    }
  }

  # Bring our own Cosmos DB (cosmosdb.tf) instead of letting the module
  # create one, so it can run in Serverless mode (pay-per-request, no
  # provisioned-throughput minimum). Its private endpoint is also created
  # in cosmosdb.tf since the module skips that step for existing resources.
  cosmosdb_definition = {
    this = {
      existing_resource_id = local.cosmosdb_id
    }
  }

  storage_account_definition = {
    this = {
      endpoints = {
        blob = {
          private_dns_zone_resource_id = azurerm_private_dns_zone.this["privatelink.blob.core.windows.net"].id
          type                         = "blob"
        }
      }
    }
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.this,
    azurerm_subnet_nat_gateway_association.agent,
    azurerm_private_endpoint.cosmosdb,
    azapi_resource_action.purge_ai_foundry,
  ]
}

# Purge a soft-deleted account of the same name before (re)creating it, and
# after destroying it — otherwise a destroy/apply cycle during iteration on
# this config can hit a 409 conflict on the account name.
resource "time_sleep" "purge_ai_foundry_cooldown" {
  destroy_duration = "20m"

  depends_on = [azurerm_subnet.agent]
}

resource "azapi_resource_action" "purge_ai_foundry" {
  method      = "DELETE"
  resource_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.CognitiveServices/locations/${var.location}/resourceGroups/${data.azurerm_resource_group.this.name}/deletedAccounts/${local.ai_foundry_name}"
  type        = "Microsoft.CognitiveServices/locations/resourceGroups/deletedAccounts@2025-09-01"
  retry = {
    error_message_regex  = ["RequestConflict"]
    interval_seconds     = 30
    max_interval_seconds = 120
  }
  when = "destroy"

  depends_on = [time_sleep.purge_ai_foundry_cooldown]
}
