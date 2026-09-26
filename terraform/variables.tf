variable "subscription_id" {
  type        = string
  default     = null
  description = "AzureサブスクリプションID。local.auto.tfvarsで指定する。nullの場合は`az account show`の現在のサブスクリプションにフォールバックする。"
}

variable "resource_group_name" {
  type        = string
  description = "デプロイ先の既存リソースグループ名。local.auto.tfvarsで指定する。"
}

variable "allowed_source_cidr" {
  type        = string
  description = "AI FoundryアカウントのパブリックエンドポイントへのアクセスをこのCIDRからのみ許可する(例: 203.0.113.5/32)。local.auto.tfvarsで指定する。"
}

variable "location" {
  type        = string
  default     = "japaneast"
  description = "Azureリージョン。既存リソースグループと同じリージョンにすること。"
}

variable "base_name" {
  type        = string
  default     = "closed"
  description = "AI Foundryリソース名に使う短いプレフィックス(3〜9文字、小文字英数字とハイフン)。"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,7}[a-z0-9]$", var.base_name))
    error_message = "base_nameは3〜9文字、小文字英数字とハイフンのみで、先頭と末尾は英数字にしてください。"
  }
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.20.0.0/16"]
  description = "VNetのアドレス空間。"
}

variable "private_endpoint_subnet_prefix" {
  type    = string
  default = "10.20.0.0/24"
}

variable "agent_subnet_prefix" {
  type        = string
  default     = "10.20.2.0/27"
  description = "Foundry Standard Agent Setup用サブネット(Microsoft.App/environments委任、/27以上)。Agentの送信はすべてここにアタッチしたNAT Gateway経由に強制される。"
}

variable "mcp_server_url" {
  type        = string
  default     = ""
  description = "Agentが呼び出すMCPサーバーのエンドポイント。Terraformリソースではなく、動作確認スクリプトでのみ使用する。TF_VAR_mcp_server_urlで指定する。"
}

variable "model_name" {
  type        = string
  default     = "gpt-6-luna"
  description = "AI Foundryアカウントにデプロイする検証用モデル。"
}

variable "model_version" {
  type    = string
  default = "2026-09-22"
}

variable "model_capacity" {
  type    = number
  default = 10
}
