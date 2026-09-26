output "ai_foundry_id" {
  value = module.ai_foundry.ai_foundry_id
}

output "ai_foundry_name" {
  value = module.ai_foundry.ai_foundry_name
}

output "ai_foundry_project_id" {
  value = module.ai_foundry.ai_foundry_project_id
}

output "nat_gateway_public_ip" {
  description = "Foundry Agentがすべての送信(MCPサーバー宛など)に使う固定送信元IP。MCPサーバー側の許可リストに登録する値。"
  value       = azurerm_public_ip.nat.ip_address
}

output "ai_foundry_endpoint" {
  description = "AI Foundryアカウントのパブリックエンドポイント。allowed_source_cidrからのみ到達可能。"
  value       = "https://${module.ai_foundry.ai_foundry_name}.services.ai.azure.com/"
}
