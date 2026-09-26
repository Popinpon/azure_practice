resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.base_name}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
}

# Subnet dedicated to private endpoints (AI Foundry account)
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.private_endpoint_subnet_prefix]
}

# Subnet for the Foundry Standard Agent Setup (network-injected agent runtime).
# default_outbound_access_enabled = false removes Azure's implicit default
# outbound path, forcing all egress through the attached NAT Gateway so the
# source IP towards the MCP server is always the NAT Gateway's static IP.
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
