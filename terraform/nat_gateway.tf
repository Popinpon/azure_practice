# snet-agent内すべての送信(egress)元IPを、この1つの固定IPにする。
# つまりFoundry Agentランタイムが外部のMCPサーバーへ送る通信の送信元IPを
# 固定し、MCPサーバー側で許可リストに登録できるようにする。
resource "azurerm_public_ip" "nat" {
  name                = "pip-${var.base_name}-nat"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1"]
}

resource "azurerm_nat_gateway" "agent" {
  name                = "nat-${var.base_name}-agent"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "agent" {
  nat_gateway_id       = azurerm_nat_gateway.agent.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "agent" {
  subnet_id      = azurerm_subnet.agent.id
  nat_gateway_id = azurerm_nat_gateway.agent.id
}
