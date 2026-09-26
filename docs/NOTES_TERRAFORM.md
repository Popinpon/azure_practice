# Terraform / AVMモジュールのハマりどころ

このリポジトリを作る過程で分かった、`README.md` / `ARCHITECTURE.md` には書いていない
Terraform・AVMモジュール周りの実装上の知見・トラブルシューティングをまとめる。
Azure運用寄りのTipsは [NOTES_AZURE.md](NOTES_AZURE.md) を参照。

### Cognitive Servicesの `network_acls.ip_rules` は `/31`・`/32` のCIDRを受け付けない

`admin_source_cidr`(例: `203.0.113.5/32`)をそのまま `ip_rules` に渡すと、apply時に
以下のエラーになる。

```
Error: creating/updating Resource ...
RESPONSE 400: 400 Bad Request
ERROR CODE: BadRequest
"message": "Invalid IP address or range 203.0.113.5/32."
```

Azure Cognitive Services の `networkAcls.ipRules` は `/31`・`/32` プレフィックスのCIDRを
サポートしていない([参考](https://learn.microsoft.com/answers/questions/individual-ip-address-firewall-rule))。
個別IPを許可したい場合はCIDRのスラッシュ部分を取り除き、素のIPアドレスとして渡す必要がある。

```hcl
ip_rules = [split("/", var.admin_source_cidr)[0]]
```

(`ai_foundry.tf` で対応済み)

### 同一applyで作るBYORリソースをモジュールに渡すと `for_each` が unknown value で壊れる

Cosmos DBをAVMモジュール任せにせず自前作成(`cosmosdb.tf`)し、
`cosmosdb_definition.this.existing_resource_id` に渡す構成にしたところ、初回applyで
以下のエラーになった。

```
Error: Invalid for_each argument
  for_each = { for k, v in var.cosmosdb_definition : k => v if v.existing_resource_id == null && var.create_byor == true }
The "for_each" map includes keys derived from resource attributes that cannot
be determined until apply...
```

原因: `existing_resource_id = azurerm_cosmosdb_account.this.id` のように、
**まだ作成されていないリソースの `.id` を参照**すると、その値はplan時点では
unknown(apply後にしか確定しない)になる。モジュール内部で
`v.existing_resource_id == null` という条件判定に使われているため、
unknownな値をnullと比較できずplanが失敗する。

回避策: リソースの `.id` 属性を直接参照せず、**サブスクリプションID・リソースグループ名・
固定した名前から手動でARMリソースIDの文字列を組み立てる**。これらはすべて
`data` ソースや変数から得られる、plan時点で確定済みの値なので、unknownにならない。

```hcl
locals {
  cosmosdb_name = "cosmos-${var.base_name}-${substr(sha1("${var.resource_group_name}-${var.base_name}-cosmos"), 0, 8)}"
  cosmosdb_id   = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${data.azurerm_resource_group.this.name}/providers/Microsoft.DocumentDB/databaseAccounts/${local.cosmosdb_name}"
}

resource "azurerm_cosmosdb_account" "this" {
  name = local.cosmosdb_name  # local.cosmosdb_idと一致する名前で作る
  # ...
}
```

同一リソース名を使う限り、Azureが実際に発行するリソースIDと `local.cosmosdb_id` は
一致する。「まだ存在しないリソースをTerraformの同一applyで作って、別のモジュールに
"既存リソース"として渡したい」という場面全般で使えるパターン。

### BYORの接続設定は `xxx_definition` と `ai_projects.xxx_connection` の両方を合わせる必要がある

`cosmosdb_definition.this.existing_resource_id` を設定しても、`ai_projects` 側の
`cosmos_db_connection` を `{ new_resource_map_key = "this" }` のままにしていると、
モジュール内部は `module.cosmosdb["this"]`(=作られていない)を参照しようとして
以下のエラーになる。

```
Error: Missing required argument
  scope = var.create_project_connections ? var.cosmos_db_id : "/n/o/t/u/s/e/d"
The argument "scope" is required, but no definition was found.
```

`cosmos_db_id` はプロジェクトの接続設定(`ai_projects.*.cosmos_db_connection`)から
解決されるのであって、`cosmosdb_definition` からではない。既存リソースを渡す場合は
**両方に同じ `existing_resource_id` を指定する**必要がある。

```hcl
ai_projects = {
  project_1 = {
    cosmos_db_connection = { existing_resource_id = local.cosmosdb_id }  # new_resource_map_keyではない
  }
}
cosmosdb_definition = {
  this = { existing_resource_id = local.cosmosdb_id }
}
```

### `Azure/avm-ptn-aiml-ai-foundry` の `cosmosdb_definition.capabilities` は実装が繋がっていない(v0.11.3時点)

変数定義には `capabilities`(例: `EnableServerless` でサーバーレス化)が存在するが、
モジュール内部の `module "cosmosdb"` 呼び出し(`main.byor.tf`)には渡されておらず、
指定しても無視される。Cosmos DBをサーバーレス化したい場合は、モジュールに作らせず
自前で `azurerm_cosmosdb_account` を作成し、`existing_resource_id` として渡すしかない
(上記2項目のパターンを参照。`cosmosdb.tf` で実施済み)。

### AI Searchのモジュール既定値は `sku = "standard"` × `replica_count = 2`

これは月$500程度(¥7〜8万)になる高額な既定値。検証用途では明示的に
`sku = "basic"` / `replica_count = 1` に上書きするべき(Private Endpointに対応する
最安のティア)。Freeティアは軽いが Private Endpoint 非対応なので選べない。

### destroy → 再apply を繰り返すと同名アカウントの409コンフリクトに当たる

AI Foundryアカウント(Cognitive Services)はソフトデリートされる。コードを試行錯誤して
`destroy` → 修正 → `apply` を繰り返すと、同名アカウントが論理削除された状態のまま残り、
再作成時に409で失敗することがある。`azapi_resource_action`(`when = "destroy"`)で
destroy時に自動パージするリソースを仕込んでおくと安全(`ai_foundry.tf` 参照)。
