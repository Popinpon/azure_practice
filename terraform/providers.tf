# Azure CLIの現在のログインセッション(az login)で認証する。
# subscription_idの既定値はnullで、その場合`az account show`の現在の
# サブスクリプションにフォールバックする。固定したい場合は
# local.auto.tfvarsで明示的に指定する。
provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
}

provider "azapi" {}
