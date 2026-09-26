# AI Foundry ⇔ MCPサーバー(OAuth認可コード)接続のTips

デプロイ後にAgentのMCPツールをOAuth認可コード方式(Microsoft Entra ID)のMCPサーバーに
繋ぐ際に分かった、公式ドキュメントだけでは分かりにくい知見をまとめる。設定手順自体は
[../mcp-foundry-setup.md](../mcp-foundry-setup.md)、MCPサーバー側でEntra IDアプリを
登録・運用する際の注意点は[mcp-server-entra-id.md](mcp-server-entra-id.md)、
Azure/Terraform自体のTipsは [azure.md](azure.md) / [terraform.md](terraform.md) を参照。

### OAuth認可(consent)とMCPツール呼び出しは別経路 — NAT Gatewayを通るのは後者だけ

`oauth_consent_request` の `consent_link` をブラウザで開いて同意する操作は、
**Agent runtimeのネットワーク経路(`snet-agent` → NAT Gateway)を一切通らない**。
単にユーザーの手元PCのブラウザがMCPサーバーの認可エンドポイントに直接アクセスするだけ
なので、MCPサーバー側のアクセスログにはNAT GatewayのIPではなく、consentした人の
手元のIP(=`allowed_source_cidr`で許可しているIP)が記録される。

このリポジトリの検証目的である「送信元IP固定」を確認する際は、**実際にAgentがMCP
ツールを呼び出した通信のログだけ**を見ること。consentアクセス時のログにNAT Gateway
以外のIPが出てきても、それは失敗ではなく設計上そうなる。

### AI FoundryはMCPのOAuth自動発見(RFC 9728 PRM)に対応していない — 全項目手動設定が必要

MCPの認可仕様では、クライアントがMCPサーバーの `/.well-known/oauth-protected-resource`
(Protected Resource Metadata)を読みに行き、認可サーバーやscopeを自動発見することを
想定している。Claude Desktop/Claude.aiなど一部のMCPクライアントはこれに対応しており、
`scopes_supported` を見て自動でscopeを決める。

しかし[Foundryの公式ドキュメント](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/mcp-authentication)
のCustom OAuth設定には、PRMや`/.well-known/oauth-authorization-server`を読みに行く
自動発見の記述が一切なく、Client ID / Client secret / Auth URL / Token URL / Refresh
URL / Scopesを**すべて手入力**する前提になっている。つまりMCPサーバー側がPRMに
対応していても、Foundry側ではその恩恵(自動設定)を受けられず、PRMが本来自動で
教えてくれるはずの値を人間が代わりに埋める必要がある。

### Entra ID (v2.0エンドポイント) は scope パラメータ必須 — 無いと `AADSTS900144`

FoundryのScopes欄は公式ドキュメント上「optional」表記だが、Entra ID
のv2.0 authorize/tokenエンドポイントは`scope`パラメータが無いリクエストを
問答無用で拒否する(`AADSTS900144: The request body must contain the following
parameter: 'scope'`)。これはMCPサーバー側の認可ロジック(トークンの`scp`クレーム
検証)より手前の、Entra自体の制約。MCPサーバーがscopeをチェックしていない
実装だったとしても、Foundry(クライアント)側はscopeを送らないとそもそも
トークンを取得できない。

さらに`offline_access`をscopeに含めないとリフレッシュトークンが発行されず、
トークン失効のたびにユーザーがconsentし直す必要が出る。

### 設定すべき正確な値は、MCPサーバー自身のPRMエンドポイントを直接叩けば分かる

Auth URL / Token URL / scope名を推測・自作する必要はない。MCPサーバーがPRMに対応
していれば、`/.well-known/oauth-protected-resource/mcp` (パスはMCPエンドポイントの
配下。末尾なしの `/.well-known/oauth-protected-resource` は404になるサーバーもあった)
を直接curlすれば、Foundryに入れるべき値がそのまま得られる。

```bash
curl -s https://<mcpサーバーのホスト名>/.well-known/oauth-protected-resource/mcp
```

```json
{
  "resource": "https://<mcpサーバーのホスト名>/mcp",
  "authorization_servers": [
    "https://login.microsoftonline.com/<tenant-id>/v2.0"
  ],
  "scopes_supported": [
    "https://<mcpサーバーのホスト名>/mcp/<スコープ名>"
  ],
  "bearer_methods_supported": ["header"]
}
```

- `authorization_servers` → テナントIDが分かるので `.../oauth2/v2.0/authorize` /
  `.../oauth2/v2.0/token` をAuth URL / Token URL(= Refresh URLもこれでよい)に
- `scopes_supported` → そのままFoundryのScopes欄に(`offline_access`は別途追記)

### Custom OAuthのredirect URLは「設定後」に発行される — 先に決め打ちできない

FoundryのCustom OAuth設定を保存すると、その場でredirect URLが発行される。
Entra側のアプリ登録には、この発行された値をそのまま追加登録する必要があり、
自分で好きなURLを決めて先に登録しておく、ということはできない。つまりEntra側の
アプリ登録(リダイレクトURI以外)→Foundry側の設定→Entra側にredirect URLを追加、
という順番が必須になる。具体的な手順は[../mcp-foundry-setup.md](../mcp-foundry-setup.md)
を参照。

### (参考) Microsoftの既知オーディエンス宛のトークンはサードパーティMCPサーバーに渡せない

Foundryの「managed OAuth」(Microsoft/MCPサーバー発行元がOAuthアプリを管理する方式)
は、既知のMicrosoftオーディエンス向けトークンをカスタム/サードパーティMCPサーバーに
渡そうとすると`Cannot pass Microsoft token to untrusted MCP endpoint.`で拒否される。
自前のMCPサーバーに繋ぐ場合は、自分のEntraアプリ登録を使う**Custom OAuth**一択になる。
