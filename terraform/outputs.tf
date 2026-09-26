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
  description = "Fixed source IP the Foundry agent uses for all outbound calls (e.g. to the MCP server). Give this to the MCP server owner to allow-list."
  value       = azurerm_public_ip.nat.ip_address
}

output "ai_foundry_endpoint" {
  description = "Public endpoint for the AI Foundry account, reachable only from admin_source_cidr."
  value       = "https://${module.ai_foundry.ai_foundry_name}.services.ai.azure.com/"
}
