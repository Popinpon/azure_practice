# AI Foundry (the unified "AIServices" account) resolves through three
# private-link zones depending on which API surface is used.
locals {
  private_dns_zone_names = [
    "privatelink.services.ai.azure.com",
    "privatelink.openai.azure.com",
    "privatelink.cognitiveservices.azure.com",
    # Required for the Standard Agent Setup's BYOR dependencies.
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
