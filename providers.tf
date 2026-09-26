# Authenticates using the Azure CLI's current session (az login).
# subscription_id defaults to null, which falls back to `az account show`'s
# current subscription; set it explicitly via local.auto.tfvars to pin it.
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
