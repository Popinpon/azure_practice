# closed_foundry

Azure AI Foundry の **Agent (MCPツール呼び出し) の送信元(egress) IPを固定**できるか検証するための
Terraform 一式です。既存リソースグループに、Standard Agent Setup (Bring Your Own VNet) +
NAT Gateway を構築します。

## 構成

- 公式 AVM パターンモジュール `Azure/avm-ptn-aiml-ai-foundry/azurerm` を使用
- AI Foundry アカウント (kind=AIServices) + Project + モデルデプロイ (既定: `gpt-6-luna`)
  - 受信: パブリックエンドポイント有効・`allowed_source_cidr` からのみ許可(network ACLs)。
    Private Endpoint も併設(Agentランタイム自身のアクセス用)
  - 送信: Agentランタイムを `snet-agent`(VNet injection)に配置し、既定の送信経路を無効化。
    NAT Gateway 経由に強制することで、MCPサーバーへの送信元IPを固定
- Standard Agent Setup の必須リソース(自前で用意して使わせるリソース。BYOR = Bring Your Own リソース):
  Cosmos DB(自前作成・Serverless) / AI Search(Basic) / Storage Account
- 動作確認用の踏み台VMは不要(パブリックアクセスをIP制限しているため、自分の端末から直接呼べる)

> **MS公式のガイドとの違い**: 公式AVMモジュールをベースにしているが、アクセス方法は変えている。
> [公式ドキュメント](https://learn.microsoft.com/ja-jp/azure/foundry/agents/how-to/virtual-networks)は
> VNet内部からのアクセス手段としてAzure Bastion(踏み台VM) / VPN Gateway / ExpressRouteを前提に
> しているが、本リポジトリはコストと手間を優先し、踏み台VMを置かずAI Foundryのパブリック
> エンドポイントを`allowed_source_cidr`のIP制限のみで直接開放している(詳細は
> [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) の①)。厳密な閉域性が必要な本番用途では
> 公式ガイドの通りBastion等を使う構成に変更してください。

## アーキテクチャ

Agentの送信元IPをNAT Gatewayで固定し、受信・内部通信・送信の3経路に分けて構成している。
図と各経路の詳細は [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) を参照。

![アーキテクチャ図](docs/architecture.png)

## 構築手順

前提条件(リソースプロバイダー登録を含む)・設定・デプロイ・動作確認・後片付け・
コスト目安は [docs/DEPLOY.md](docs/DEPLOY.md) にまとめています。

## ドキュメント一覧

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — 通信経路・サブネット構成の詳細
- [docs/DEPLOY.md](docs/DEPLOY.md) — 構築手順(前提・設定・デプロイ・動作確認・後片付け・コスト目安)
- [docs/tips/terraform.md](docs/tips/terraform.md) — Terraform/AVMモジュールのハマりどころ
- [docs/tips/azure.md](docs/tips/azure.md) — Azure運用のTips
- [docs/tips/mcp-oauth.md](docs/tips/mcp-oauth.md) — AgentからMCPサーバーへのOAuth接続のハマりどころ
- [docs/tips/container-apps.md](docs/tips/container-apps.md) — Azure Container Apps運用のTips(送信元IPの確認方法など)
