# Azure運用のTips

このリポジトリを作る過程で分かった、`README.md` / `ARCHITECTURE.md` には書いていない
Azureサービス自体の挙動・運用面の知見をまとめる。Terraform/AVMモジュール周りの
ハマりどころは [terraform.md](terraform.md) を参照。

### 既存のFoundryリソースに、あとから送信方向のVNet injectionだけ追加することはできない

[公式ドキュメント](https://learn.microsoft.com/azure/foundry/how-to/configure-private-link)に
明記されている制約: 「委任済みのサブネットを別のサブネットに変更することはできない」
「既存のFoundryデプロイに事後的に送信方向のVNet injectionを追加することはできない。
送信方向のネットワーク分離を追加するにはFoundryを作り直す必要がある」。

つまり`ai_foundry.tf`の`network_injections`は**最初のアカウント作成時に確定させる
必要がある**設定で、後から「やっぱりVNet injectionを有効にしたい」と`terraform apply`
で追加しても反映されない(そもそもTerraform的にも`create_ai_agent_service`や
`network_injections`は実質的に作成時のみ有効なプロパティとして扱われる)。試すなら
最初から今回の構成(BYOR + network_injections)で作ること。

### モデルの実際の提供状況は `az cognitiveservices model list` で確認するのが確実

MS Learnのリージョン対応表はモデルのGAから数日〜数週間、更新が追いつかないことがある
(このリポジトリでも `gpt-6-luna` のリージョン対応表記が古く、実際には使えるのに
ドキュメント上は載っていないように見えるケースがあった)。デプロイ前に対象リージョンで
実際に使えるか、Azure自身に問い合わせるのが最も確実。

```bash
az cognitiveservices model list --location japaneast \
  -o json | jq '[.[] | select(.model.name == "gpt-6-luna")]'
```

### `Microsoft.App` プロバイダー未登録だと、延々と`Creating`のまま最終的に`Failed`になる

Standard Agent Setup(VNet injection)は、Agentランタイムのホスティングに
Container Apps(`Microsoft.App/environments`)を使う。サブスクリプションで
`Microsoft.App`(と`Microsoft.ContainerService`)が未登録のままapplyすると、
ARMはリクエスト自体は受理してしまい、**エラーも出さずに1〜2時間近く`Creating`のまま
進み、最終的に`Failed`になる**。このリポジトリでも実際にこの状態を踏んだ。

最終的なエラーメッセージも要領を得ない(以下のように「個々のkindは成功している」と
書きつつ全体は失敗、という紛らわしい内容になる)。

```json
{
  "status": "Failed",
  "error": {
    "message": "The resource operation completed with terminal provisioning state 'Failed'.",
    "details": [{
      "message": "Failed to Create the resource. Provisioning state: Failed",
      "details": [{
        "message": "Kind: OpenAI, ProvisioningState: Succeeded, ...; Kind: TextAnalytics, ProvisioningState: Succeeded, ..."
      }]
    }]
  }
}
```

apply前に、必要なリソースプロバイダーがすべて登録済みか確認しておく
([docs/DEPLOY.md](../DEPLOY.md) の前提条件を参照)。

```bash
az provider show --namespace Microsoft.App --query registrationState -o tsv
# "NotRegistered" なら
az provider register --namespace Microsoft.App
```

途中経過を見たい場合は `provisioningState` を直接ポーリングするとよい。

```bash
az cognitiveservices account show -g <rg> -n <name> \
  --query "properties.provisioningState" -o tsv
```

### `Failed`になったアカウントをTerraformが再作成しようとすると409 `FlagMustBeSetForRestore`で失敗する

上記のように一度`Failed`になったリソースは、Terraform上は`tainted`(要再作成)として
扱われる。次の`apply`でTerraformは①既存の(失敗した)アカウントを`destroy`→
②同名で`create`、という順で処理するが、①の`destroy`はAzure上ではソフトデリートに
なるため、②の`create`が以下のエラーで失敗する。

```
RESPONSE 409: 409 Conflict
ERROR CODE: FlagMustBeSetForRestore
"message": "An existing resource with ID '...' has been soft-deleted.
 To restore the resource, you must specify 'restore' to be 'true' ...
 If you don't want to restore existing resource, please purge it first."
```

`ai_foundry.tf`の`azapi_resource_action`(destroy時パージ)は、**環境全体を
destroyする時しか発火しない**ため、この「単一リソースの差し替え」のケースは
カバーされない。手動でパージしてから再applyする。

```bash
az cognitiveservices account purge -g <rg> -n <name> -l <location>
terraform apply
```

### AI SearchのServerlessは(2026年9月時点)まだ閉域構成に向かない

2026-09-13からAI SearchにServerless(Developer)ティアのプレビューが始まっているが、
以下の理由で今回のような閉域構成には使えない。

- パブリックプレビューでSLAなし、本番非推奨
- 「Private networking for indexers: 非対応」「Shared Private Link: 対応予定なし」と明記
  されており、Private Endpoint対応が明言されていない
- 他ティアとの相互移行不可
- 提供リージョンが限定的

GA後にPrivate Endpoint対応が入ったら乗り換えを検討する価値はあるが、現時点ではBasic
SKU(Dedicatedモデル)を使うしかない。
