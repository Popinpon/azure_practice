# 構築手順

[README.md](../README.md) の概要を踏まえた、セットアップ〜デプロイ〜動作確認〜
後片付けまでの手順。

## 前提

- `az login` 済みであること
- 対象のリソースグループが存在すること(このコードでは作成しません。既存のものを利用します)
- (既定の `location = japaneast` / `model_name = gpt-6-luna` のまま使う場合は確認不要。
  変更する場合のみ)利用するモデルが対象リージョンで提供されていること
  - `az cognitiveservices model list --location <region>` で確認できます
- **以下のリソースプロバイダーがサブスクリプションに登録済みであること**

  未登録のまま`apply`すると、ARMはリクエストを一旦受理してしまい、Standard Agent
  Setup(AI Foundryアカウント)の作成が延々と`Creating`のまま進み、最終的に
  `Failed`になる(数十分後)。エラーが分かりにくく気づきにくいので、事前確認を推奨。
  詳細: [docs/tips/azure.md](tips/azure.md)。

  - `Microsoft.App` ← **特に見落としやすい**。Agentランタイムのホスティング
    (VNet injection先のContainer Apps環境)に必須
  - `Microsoft.ContainerService`
  - `Microsoft.CognitiveServices`
  - `Microsoft.MachineLearningServices`
  - `Microsoft.Search`
  - `Microsoft.KeyVault`
  - `Microsoft.Storage`
  - `Microsoft.Network`

  確認・登録コマンド:

  ```bash
  # 登録状況を一括確認
  for ns in Microsoft.App Microsoft.ContainerService Microsoft.CognitiveServices \
            Microsoft.MachineLearningServices Microsoft.Search Microsoft.KeyVault \
            Microsoft.Storage Microsoft.Network; do
    echo "$ns: $(az provider show --namespace "$ns" --query registrationState -o tsv)"
  done

  # 未登録のものだけ登録(数分かかる)
  az provider register --namespace Microsoft.App
  ```

## ディレクトリ構成

```
.
├── README.md
└── terraform/       # Terraformコード一式(このディレクトリで実行する)
    ├── *.tf
    ├── local.auto.tfvars.example
    └── local.auto.tfvars   # 自分で作成する。gitignore対象
```

## 設定 (local.auto.tfvars)

サブスクリプション・リソースグループ・許可IPはコードにハードコードせず、`*.auto.tfvars` ファイルで
渡します。`*.auto.tfvars` は `terraform plan`/`apply` 実行時に**同じディレクトリ内のものが
自動で読み込まれる**ので、`source` や `export` は不要です(別ディレクトリに置くと自動読み込みされ
ないので、`terraform/` 配下に置いてください)。

```bash
cd terraform
cp local.auto.tfvars.example local.auto.tfvars
```

`local.auto.tfvars` を編集(`local.auto.tfvars` は `.gitignore` 済みでコミットされません):

```hcl
# subscription_id を指定しなければ az account show の現在のサブスクリプションが使われる
# subscription_id     = "00000000-0000-0000-0000-000000000000"
resource_group_name = "rg-hogehoge"
admin_source_cidr   = "203.0.113.5/32"   # 自分のグローバルIP。curl -s https://ifconfig.me で確認
```

`admin_source_cidr` は「AI Foundryのパブリックエンドポイントへの直接アクセスを許可する送信元」を
CIDR 表記(IPアドレス + プレフィックス長)で指定します。`/32` は「そのIP1つだけ許可」という意味です。
自宅回線・モバイル回線などでIPが変わると呼べなくなるので、その場合は現在のIPを確認し直して
`local.auto.tfvars` を更新 → `terraform apply` してください。

## デプロイ

```bash
cd terraform   # 上の設定済みなら既にこのディレクトリにいるはず
terraform init
terraform plan
terraform apply
```

Standard Agent Setup(AI Foundryアカウント本体)の作成には時間がかかることがあります
(公式見積もりは30〜45分だが、それ以上かかることもある)。`Still creating...` が
続いても、リソースプロバイダー登録(上記)さえ済んでいれば異常ではありません。

## 動作確認 (送信元IP固定のテスト)

1. `terraform output nat_gateway_public_ip` で固定IPを確認し、検証用MCPサーバー側の許可リストに登録
2. `terraform output ai_foundry_endpoint` のエンドポイントに対し、`admin_source_cidr` の端末から
   Foundry Agent SDK / REST API でMCPツールを設定したAgentを作成・実行
3. MCPサーバー側のアクセスログを確認し、送信元IPが `nat_gateway_public_ip` と一致することを確認

`admin_source_cidr` 以外のIPから同じエンドポイントを叩くと拒否されることも合わせて確認してください。
AgentのMCPツールをOAuth認可コード方式で接続する場合のハマりどころは
[docs/tips/mcp-oauth.md](tips/mcp-oauth.md) を参照してください。

## 後片付け

```bash
terraform destroy
```

## コスト目安

このリソース一式は時間課金のものが多いため、検証が終わったら `terraform destroy` してください。
概算(japaneast、放置した場合の月額目安):

| リソース | 月額目安 |
|---|---|
| AI Search (Basic) | 約¥11,000 |
| NAT Gateway + 固定Public IP | 約¥5,300 |
| Private Endpoint ×4 | 約¥4,400 |
| Private DNS Zone ×6 | 約¥450 |
| Cosmos DB (Serverless) | ほぼ¥0(従量課金) |
| Storage Account | ほぼ¥0 |

半日〜1日程度の検証で `destroy` するなら実費は数百〜¥1,000程度に収まります。

## トラブルシューティング

- モデルのデプロイに失敗する場合は `variables.tf` の `model_name` / `model_version` /
  `model_capacity` を利用可能なものに変更してください。
- そのほかTerraform/Azure/MCP接続で遭遇したハマりどころは
  [docs/tips/](tips/) 配下にまとめています。
