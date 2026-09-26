# アーキテクチャ

Foundry Agent(MCPツール呼び出し)の送信元IPを固定し、MCPサーバー側で許可リストとして
使えるようにするための構成。受信・内部通信・送信の3つの経路に分けて説明する。

![アーキテクチャ図](architecture.svg)

## 通信経路

### ① 管理者 → AI Foundry(パブリック・IP許可)

AI Foundry のパブリックエンドポイントは有効にしたまま、`network_acls` で
`admin_source_cidr` 以外からの接続を拒否している。動作確認用の踏み台VMを用意しなくても、
手元の端末から直接 Agent API / Foundry Portal を呼べる。

### ② Agent runtime ↔ BYOR(Private Link・VNet内部)

Agent の会話履歴・スレッド・エージェント定義(Cosmos DB)、ベクトルストア(AI Search)、
アップロードファイル(Storage Account)は Standard Agent Setup の必須リソース(BYOR)。
これらはパブリックアクセスを一切許可しておらず、Private Endpoint 経由でのみ到達できる。
`snet-agent` からは同一 VNet 内の `snet-private-endpoints` に直接ルーティングされる。

これらは MCP を呼ぶかどうかに関わらず、Standard Agent Setup(= VNet injection)を使う以上
必須のリソースになる。詳細: [Set up standard agent resources for Foundry Agent Service](https://learn.microsoft.com/azure/foundry/agents/concepts/standard-agent-setup)

### ③ Agent runtime → NAT Gateway → MCPサーバー(送信元IP固定)ーーこの検証の本題

`snet-agent` は既定の送信経路を持たない(`default_outbound_access_enabled = false`)。
これにより Agent がインターネット上の MCP サーバーへ送信する通信は、サブネットに
アタッチされた NAT Gateway の固定 Public IP を経由するルート以外に存在しなくなる。

MCP サーバー側は、この NAT Gateway の Public IP(`terraform output nat_gateway_public_ip`)
1つだけを許可リストに登録すればよい。

## サブネット構成

| サブネット | CIDR | 用途 |
|---|---|---|
| `snet-private-endpoints` | `10.20.0.0/24` | AI Foundry / Cosmos DB / AI Search / Storage の Private Endpoint |
| `snet-agent` | `10.20.2.0/27` | Agent runtime。`Microsoft.App/environments` 委任、既定送信経路なし |

## 図中の凡例

- **青**: 管理者PC → AI Foundry パブリックエンドポイント(`admin_source_cidr` のみ許可)
- **グレー破線**: Agent runtime ↔ Cosmos DB / AI Search / Storage(Private Link・VNet内部)
- **オレンジ**: Agent runtime → NAT Gateway → MCPサーバー(送信元IP固定)

図中のアイコンはAzure公式アセットではなく、サービスカテゴリの配色
(AI = マゼンタ系、Networking = 青系)に準拠した簡易ピクトグラム。
