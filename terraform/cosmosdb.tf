# ai_foundryモジュール内蔵の「自前リソースを用意して使わせる」経由ではなく、
# 直接ここで作成することで
# Serverlessモードにできるようにしている。AVMモジュールは現状
# `capabilities`(サーバーレス化)を配線しておらず、Standard Agent Setupの
# プロビジョンドスループット下限(3000 RU/s以上)をそのまま使うと放置時に
# 実費が発生する。Serverlessならリクエスト従量課金で最低料金がない。
#
# name/idは(他リソースの計算結果ではなく)静的な入力のみから導出している。
# こうすることで、このアカウントがまだ存在しない初回applyの時点でも、
# ai_foundryモジュールの`existing_resource_id`にplan時点で確定した値を
# 渡せる。代わりに azurerm_cosmosdb_account.this.id を使うと、plan時点では
# 未確定(unknown)になり、モジュール側のfor_eachが壊れる。
locals {
  # 本当はsubscription_idもハッシュの種に含めて衝突耐性を上げたいところだが、
  # Projectが一度Capability Hostを持つとcosmos_db_connectionの差し替えができない
  # (「in use by the workspace capability host」でAPIから拒否される。Project自体の
  # 作り直しが必要)ため、既存デプロイへの影響が大きすぎると判断して見送っている。
  # 詳細: docs/tips/terraform.md
  cosmosdb_name = "cosmos-${var.base_name}-${substr(sha1("${var.resource_group_name}-${var.base_name}-cosmos"), 0, 8)}"
  cosmosdb_id   = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${data.azurerm_resource_group.this.name}/providers/Microsoft.DocumentDB/databaseAccounts/${local.cosmosdb_name}"
}

resource "azurerm_cosmosdb_account" "this" {
  name                = local.cosmosdb_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  public_network_access_enabled = false
  local_authentication_enabled  = false

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }
}

resource "azurerm_private_endpoint" "cosmosdb" {
  name                = "pe-${azurerm_cosmosdb_account.this.name}"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "psc-${azurerm_cosmosdb_account.this.name}"
    private_connection_resource_id = azurerm_cosmosdb_account.this.id
    subresource_names              = ["Sql"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.this["privatelink.documents.azure.com"].id]
  }
}
