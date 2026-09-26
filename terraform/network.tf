resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.base_name}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
}

# Private Endpoint専用のサブネット(AI Foundryアカウント用)
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_endpoint_subnet_prefix]
}

# Foundry Standard Agent Setup用サブネット(VNet injectionされたAgentランタイム)。
# default_outbound_access_enabled = false でAzureの暗黙の既定送信経路を
# 無効化し、すべての送信をアタッチしたNAT Gateway経由に強制する。これに
# より、MCPサーバーへの送信元IPは常にNAT Gatewayの固定IPになる。
resource "azurerm_subnet" "agent" {
  name                            = "snet-agent"
  resource_group_name             = data.azurerm_resource_group.this.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [var.agent_subnet_prefix]
  default_outbound_access_enabled = false

  delegation {
    name = "Microsoft.App.environments"

    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}
