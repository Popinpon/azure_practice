# AI Foundry (統合されたAIServicesアカウント) は、使うAPI面によって
# 3つのprivate-linkゾーンのいずれかで名前解決される。
locals {
  private_dns_zone_names = [
    "privatelink.services.ai.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.cognitiveservices.azure.com",
    # Standard Agent Setupで自前で用意して使わせる依存リソース用に必要。
    "privatelink.documents.azure.com",   # Cosmos DB
    "privatelink.search.windows.net",    # Azure AI Search
    "privatelink.blob.core.windows.net", # Storage Account
  ]
}

resource "azurerm_private_dns_zone" "this" {
  for_each = toset(local.private_dns_zone_names)

  name                = each.value
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = azurerm_private_dns_zone.this

  name                  = "link-${replace(each.key, ".", "-")}"
  resource_group_name   = data.azurerm_resource_group.this.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

locals {
  ai_foundry_dns_zone_names = [
    "privatelink.services.ai.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.cognitiveservices.azure.com",
  ]
}
