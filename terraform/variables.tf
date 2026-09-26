variable "subscription_id" {
  type        = string
  default     = null
  description = "Azure subscription ID. Set in local.auto.tfvars; null falls back to `az account show`'s current subscription."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group to deploy into. Set in local.auto.tfvars."
}

variable "admin_source_cidr" {
  type        = string
  description = "CIDR allowed to call the AI Foundry account's public endpoint directly (e.g. 203.0.113.5/32). Set in local.auto.tfvars."
}

variable "location" {
  type        = string
  default     = "japaneast"
  description = "Azure region. Must match the existing resource group's region."
}

variable "base_name" {
  type        = string
  default     = "closed"
  description = "Short name prefix used for AI Foundry resource naming (3-9 chars, lowercase alphanumeric/hyphen)."

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,7}[a-z0-9]$", var.base_name))
    error_message = "base_name must be 3-9 chars, lowercase letters/digits/hyphens, starting and ending with an alphanumeric char."
  }
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.20.0.0/16"]
  description = "Address space for the VNet."
}

variable "private_endpoint_subnet_prefix" {
  type    = string
  default = "10.20.0.0/24"
}

variable "agent_subnet_prefix" {
  type        = string
  default     = "10.20.2.0/27"
  description = "Subnet for the Foundry Standard Agent Setup (delegated to Microsoft.App/environments, /27 or larger). All agent egress is forced through the NAT Gateway attached here."
}

variable "mcp_server_url" {
  type        = string
  default     = ""
  description = "MCP server endpoint the agent will call, used only in the test script (not a Terraform resource). Set via TF_VAR_mcp_server_url."
}

variable "model_name" {
  type        = string
  default     = "gpt-6-luna"
  description = "Model to deploy on the AI Foundry account for testing."
}

variable "model_version" {
  type    = string
  default = "2026-09-22"
}

variable "model_capacity" {
  type    = number
  default = 10
}
