# 新規作成せず、既存のリソースグループを参照する。
data "azurerm_resource_group" "this" {
  name = var.resource_group_name
}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}
