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
  `.../oauth2/v2.0/token` をAuth URL / Token URLに(**Refresh URLは空欄のままにする**。
  理由は次項)
- `scopes_supported` → そのままFoundryのScopes欄に(`offline_access`は別途追記)

### Refresh URLを埋めると500エラーになる既知の不具合がある — 空欄のままにする

FoundryのCustom OAuth設定で、Refresh URL欄にToken URLと同じ値を入れて保存すると、
接続の作成/利用時に以下のような`500 Internal Server Error`(`server_error`)になる
ことがある。

```json
{"error":{"message":"The server had an error processing your request. Sorry about that! ...",
"type":"server_error","code":"server_error","request_id":"..."}}
```

同じ症状がMicrosoft Q&Aでも報告されている
([Azure AI Foundry custom MCP tool with OAuth Identity Passthrough returns
redirectUrl: null and fails when Refresh URL is set](https://learn.microsoft.com/en-us/answers/questions/5806486/azure-ai-foundry-custom-mcp-tool-with-oauth-identi))。
Custom OAuth設定のpreview機能側のバグと見られ、リージョン固有の場合もあるようだが、
japaneastでも再現した。

**対処**: Refresh URLは空欄のままにする。ただしその場合、保存時に発行される
redirect URLが`redirectUrl: null`になることがある。その場合は、以下の形式で
リダイレクトURIを手動で組み立て、Entra側アプリ登録のWebプラットフォームに追加する。

```
https://cas.services.azure-ai.net/app/oauth/redirect?connectionId=<接続名>
```

(`<接続名>`はFoundry Portalで付けたconnectionの名前)

一度おかしくなった接続(Refresh URLを埋めて保存してしまった等)は、編集で直せない
ことがある。その場合は接続自体を削除して作り直す方が早い。

### `gpt-6-luna`はAgent ServiceのMCPツール呼び出しで500になる — `gpt-5.6-luna`なら動く

Client ID・Refresh URL・接続の作り直しなど設定周りを全部直しても、Responses APIに
MCPツール付きAgentで呼び出すと`500 server_error`になり続けることがある。この場合、
**モデル自体(`model_name`。既定は`gpt-6-luna`)が原因**の可能性がある。

```json
{"error":{"message":"The server had an error processing your request. Sorry about that! You can retry your request, or contact us through an Azure support request at: https://go.microsoft.com/fwlink/?linkid=2213926 if you keep seeing this error. (Please include the request ID ... in your email.)","type":"server_error","param":null,"code":"server_error","request_id":"..."}}
```

新規のconnection・新規のAgentの組み合わせで試しても、request IDだけ変わって同じ
エラーが再現し続けるのが特徴(接続やAgentの状態が壊れているのではなく、モデルが
原因であることを示唆する)。

切り分け方: ツールを一切付けていないAgentへの素のチャット([mcp-foundry-setup.md](../mcp-foundry-setup.md)
手順4の`create_version`でtools無しにする、またはFoundry Portalで直接作る)が成功するなら、
Project/Accountやconnectionの設定自体は壊れていない。その状態でMCPツール付きだけが
500になるなら、モデルを疑う。

実際に`gpt-6-luna`→`gpt-5.6-luna`へ変更したところ、同じツール・接続設定のまま解消した。
`gpt-6-luna`がAgent ServiceのMCPツール呼び出し(preview機能)に対応していない可能性がある。
`terraform/variables.tf`の`model_name`の既定値は本記事時点では`gpt-6-luna`のままなので、
MCPツールを使う検証では`gpt-5.6-luna`などに変更したデプロイを試すこと。

### `azd ai connection create`はテナント跨ぎ環境で誤ったテナントのトークンを使う既知バグがある

Foundry Portalをポチポチする代わりに`azd ai connection create`(実体は
`azure.ai.connections`というBeta拡張)で接続をスクリプト的に作ろうとすると、
複数テナントに所属している環境で以下のようなエラーになることがある。

```
ERROR CODE: Tenant provided in token does not match resource token
{"error":{"code":"Tenant provided in token does not match resource token",
"message":"Token tenant <A> does not match resource tenant."}}
```

`azd auth login --tenant-id <正しいテナント>`で明示的にログインし直しても再現する。
GitHubのazure-devリポジトリに同種の既知Issueがある
([#5974](https://github.com/Azure/azure-dev/issues/5974)、
[#9712](https://github.com/Azure/azure-dev/issues/9712))。`AzureDeveloperCliCredential`
を内部で呼ぶ際にtenant-idを明示的に渡していないバグで、ログイン中アカウントの
**ホームテナント**のトークンを使ってしまい、対象サブスクリプションのテナントと
食い違う。ゲスト/クロステナント構成(今回のように複数テナントに所属している状況)
で起きやすい。

ユーザー側の確実なワークアラウンドは見つかっていない。この状況になったら
Foundry Portalでの手動作成に切り替えるのが早い。

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

### `project_connection_id`を使わず、`MCPTool.authorization`にトークンを直接渡す方式もある

ここまでの手順はすべて、Foundry Portalで作った**connection**(`project_connection_id`)
経由でOAuth Identity Passthroughを使う前提だった。しかし`MCPTool`(Python SDK:
`azure.ai.projects.models.MCPTool`)には、それとは別に以下のフィールドがある。

```
authorization: Optional[str]   # MCPサーバーに渡すOAuthアクセストークンを直接指定
headers: Optional[dict[str, str]]  # 任意のカスタムヘッダー
```

`project_connection_id`の代わりにこの`authorization`(または`headers`でAuthorization
ヘッダーを直接組み立てる)を使うと、**Foundry Portal側のconnection作成もconsentフロー
(`oauth_consent_request`)も一切経由せず**、アプリ側で事前に取得したトークンをそのまま
MCPサーバー呼び出しに使わせられる。実機で確認済み(`scripts/run-mcp-agent-direct-token.py`)
で、`mcp_list_tools`→`mcp_call`まで一発で成功する。

この方式が有効なユースケース: **Foundryを呼び出す側の身元(RBAC対象)はマネージドID
などシンプルなもの1つに保ちつつ、MCPサーバー側の権限だけをエンドユーザーごとに変えたい**
場合。`project_connection_id`方式だと、OAuth Identity Passthroughのconsent紐づけ
キーが「Foundryを呼んでいるプリンシパル」になってしまうため、呼び出し元を単一の
マネージドIDに統一すると、MCPサーバー側の権限もユーザー間で共有されてしまう(consentを
最初にした1人のトークンを全員が使い回す形になる)。`authorization`に自前で用意した
ユーザーごとのトークンを都度渡せば、この制約を回避できる。

トレードオフとして、トークンの取得(誰のどんなスコープのトークンをどう取るか)・
有効期限切れ時のリフレッシュは、Foundryに任せず**アプリ側が自前で全部面倒を見る**
必要がある(Foundryの自動リフレッシュ・consent管理の恩恵を受けられない)。
