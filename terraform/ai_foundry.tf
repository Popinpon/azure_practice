# Azure AI FoundryアカウントとStandard Agent Setup。
# - 受信: パブリックエンドポイントは有効だが、network_aclsで
#   admin_source_cidrに制限している。踏み台VMなしで自分の端末から
#   直接呼べる。Agentランタイム自身がアカウントにアクセスするために
#   Private Endpointも併設(create_private_endpoints = true)している。
# - 送信(この検証の本題): create_ai_agent_service + network_injectionsで
#   Agentランタイムをsnet-agentに配置している。このサブネットは既定の
#   送信経路を持たず、nat_gateway.tfのNAT Gateway経由に強制される。
#   そのためAgentが外部のMCPサーバーへ送る通信は、すべてこのNAT
#   GatewayのPublic IPを送信元にする。
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
    # パブリックエンドポイントは有効だがadmin_source_cidrに固定。
    # 踏み台なしで直接呼べる一方、それ以外からは拒否する。
    # Cognitive Servicesのnetwork_acls.ip_rulesは/31・/32のCIDRを受け付けない
    # ため、admin_source_cidrがCIDR表記でもIP部分だけを渡す。
    public_network_access_enabled = true
    network_acls = {
      default_action = "Deny"
      ip_rules       = [split("/", var.admin_source_cidr)[0]]
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

  # sku/replica_countはモジュールの既定値(standard x replica 2、月$500程度)
  # から、Private Endpointに対応する範囲で最安のティアに変更している。
  # 使い捨ての検証環境のため。
  ai_search_definition = {
    this = {
      private_dns_zone_resource_id = azurerm_private_dns_zone.this["privatelink.search.windows.net"].id
      sku                          = "basic"
      replica_count                = 1
    }
  }

  # モジュールに作らせず、自前で用意したCosmos DB(cosmosdb.tf)を使わせる。
  # Serverlessモード(リクエスト従量課金、プロビジョンドスループットの
  # 下限なし)にするため。Private Endpointも、モジュールが既存リソース
  # に対してはこのステップをスキップするのでcosmosdb.tf側で作成している。
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

# 同名アカウントがソフトデリート状態で残っていると(再)作成できないため、
# 作成前・destroy後にパージする。このコードを試行錯誤する中で
# destroy→apply を繰り返すと、アカウント名の409コンフリクトに当たるため。
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
