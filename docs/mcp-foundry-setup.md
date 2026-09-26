# AI Foundry: MCPツールをOAuth認可コードで接続する手順

Agentの `mcp` ツールを、OAuth認可コード方式で認証するMCPサーバーに接続するための、
Foundry Portal側の設定手順。FoundryのCustom OAuth設定自体はOAuth 2.0の一般的な項目
(Client ID / Auth URL / Token URL / Scopesなど)で、任意のOAuthプロバイダーに対応する
汎用機能。

MCPサーバー側でEntra IDアプリを登録・運用する際の注意点は
[tips/mcp-server-entra-id.md](tips/mcp-server-entra-id.md)、この方式特有の
ハマりどころは[tips/mcp-oauth.md](tips/mcp-oauth.md)を参照。

## 前提

- MCPサーバー用のOAuthクライアント登録(呼び方はプロバイダーによって異なる。
  Entra IDでは「アプリの登録」)が完了していること(client ID / client secret /
  認可・トークンエンドポイント / スコープ名を把握していること。Entra IDの場合の
  登録の流れは[tips/mcp-server-entra-id.md](tips/mcp-server-entra-id.md)を参照)
- MCPサーバーのエンドポイントURLが分かっていること

## 1. 設定値を集める

必要な値は次の3つから集める。

1. 自分で作成したOAuthクライアント登録の内容(Client ID / Client secretなど)。
   登録手順はプロバイダー固有(Entra IDの場合は[tips/mcp-server-entra-id.md](tips/mcp-server-entra-id.md)参照)
2. OAuthプロバイダーの公式リファレンス(Entra IDの場合は
   [Microsoft Entra ID のエンドポイント一覧](https://learn.microsoft.com/entra/identity-platform/v2-protocols#endpoints))
3. 上記に記載が無い・確認したい場合は、以下のスクリプト

[scripts/get-oauth-endpoints.py](../scripts/get-oauth-endpoints.py)にMCPサーバーの
PRM URLを渡すと、Foundryにそのまま入力できる値が出力される
(`scripts/.env`に`TF_VAR_mcp_server_url`を設定していればPRM URLの指定も省略できる。
`.env`の作り方は[scripts/.env.example](../scripts/.env.example)参照。以下は
`uv sync`済み・`scripts/`ディレクトリで実行するのが前提)。

```bash
cd scripts
uv run ./get-oauth-endpoints.py https://<mcpサーバーのホスト名>/.well-known/oauth-protected-resource/mcp
# .envにTF_VAR_mcp_server_urlを設定済みなら
uv run ./get-oauth-endpoints.py
```

```
server_url:  https://<mcpサーバーのホスト名>/mcp
Auth URL:    https://<認可サーバーのホスト>/.../authorize
Token URL:   https://<認可サーバーのホスト>/.../token
Refresh URL: https://<認可サーバーのホスト>/.../token
Scopes:      https://<mcpサーバーのホスト名>/mcp/<スコープ名> offline_access
```

MCPサーバーがPRMに対応していない場合や、issuerがOpenID Connectのdiscoveryに対応
していない場合はエラーになる。その場合は公式リファレンス等から直接調べる(OAuth 2.0
のみの認可サーバーなら、RFC 8414の`{issuer}/.well-known/oauth-authorization-server`
を試す)。

Foundryには上記に加えて、Client ID / Client secretを入力する。

| Foundry側の項目 | 値 |
|---|---|
| server_url / Auth URL / Token URL / Scopes | 上記スクリプトの出力(Entra IDの場合、Auth/Token URLの規則は安定しているのでスクリプトを省いて`https://login.microsoftonline.com/<tenant-id>/v2.0/{authorize,token}`と決め打ちしてもよい) |
| Refresh URL | **空欄のままにする**(既知の不具合を回避するため。詳細は[tips/mcp-oauth.md](tips/mcp-oauth.md)参照) |
| Client ID | OAuthプロバイダー側のクライアント登録の値 |
| Client secret | OAuthプロバイダー側のクライアント登録の値。MCPサーバー側がconfidential clientを要求する場合のみ必須(public client・PKCEのみの場合は不要。Entra IDでの登録は[tips/mcp-server-entra-id.md](tips/mcp-server-entra-id.md)参照) |

## 2. Foundry Portalでツールを接続する

対象プロジェクト → **Build** → **Connect a tool** → **Custom** → **MCP**。

1. `server_url` / `server_label`(任意の識別名)を入力
2. 認証方式に **OAuth Identity Passthrough** → **Custom OAuth** を選択
3. 手順1で組み立てた値(Client ID / Client secret / Auth URL / Token URL / Scopes)を
   入力して保存。**Refresh URLは空欄のままにする**(埋めると保存/利用時に500エラーに
   なる既知の不具合がある。詳細は[tips/mcp-oauth.md](tips/mcp-oauth.md)参照)

保存すると **redirect URL** が発行される。これをコピーしておく(Refresh URLを空欄に
した場合、`redirectUrl: null`になることがある。その場合の対処も
[tips/mcp-oauth.md](tips/mcp-oauth.md)参照)。

## 3. OAuthプロバイダー側にリダイレクトURIを登録する

OAuthプロバイダーのクライアント登録の管理画面で、手順2で発行されたredirect URLを
リダイレクトURIとして追加する。登録方法(client種別の区別有無・呼び方)はプロバイダー
によって異なる。

**Entra IDの場合**: 「プラットフォーム」という単位でconfidential/public clientを
区別する。対象アプリの登録(Entra IDでのクライアント登録の呼び方) → **認証** 画面で、

1. プラットフォームを追加する。手順1でClient secretを使ったかどうかで種類を選ぶ
   - secretあり → **Web**
   - secret無し → **モバイルおよびデスクトップアプリケーション**など
2. そのプラットフォームのリダイレクトURIに、redirect URLを追加する

## 4. Agentにツールを追加する

Foundry Agent Serviceは`AIProjectClient`経由(project-scoped endpoint、
`https://<account>.services.ai.azure.com/api/projects/<project>`)で呼ぶ。
`mcp`ツールはResponses APIの`tools`に直接渡すのではなく、`PromptAgentDefinition`に
持たせてAgentとして作成し、実行時に`agent_reference`で参照する。
`project_connection_id`は、Foundry Portalの対象ツール詳細画面(**Build** →
接続したツールを開く)の「プロジェクト接続 ID」欄に表示されている値を使う
(公式サンプルでは`<connection名>`のような短い名前だが、Portal上はARMリソースIDの
フルパス`/subscriptions/.../connections/<connection名>`を表示するため、動かない場合は
両方試す)。実際のコードは[scripts/run-mcp-agent.py](../scripts/run-mcp-agent.py)を参照
(`AIProjectClient` → `get_openai_client()` → `MCPTool` / `PromptAgentDefinition` →
`agents.create_version()`という流れ)。

### Agentの作成・更新には`Foundry User`ロールが必要

`create_version`は`Microsoft.CognitiveServices/accounts/AIServices/agents/write`を要求する。
`az login`しているだけでは足りず、Foundryリソースのスコープに自分の(または呼び出し元の)
principalへ**Foundry User**ロール(旧称 Azure AI User)の割り当てが要る。

```
azure.core.exceptions.HttpResponseError: (UserError) Identity(object id: ...) does not have
permissions for Microsoft.CognitiveServices/accounts/AIServices/agents/write actions.
```

割り当て先ごとに、やり方は主に2通り。

1. **自分自身に割り当てる場合(Foundry Portalのボタン)**: 対象プロジェクトでAgentの作成画面を
   開くと、権限不足時に「Foundry ユーザー ロールを割り当てる」ボタンが出る場合がある。
   それを押すだけでよい(反映まで数分かかることがある)。**自分自身にしか使えない。**
2. **マネージドID/サービスプリンシパルに割り当てる場合(Azure PortalのIAM画面)**: 対象
   リソースの**アクセス制御(IAM)** → **ロールの割り当ての追加**で、割り当て先に対象の
   マネージドID(または作成済みのアプリ登録)を選ぶ。マネージドIDはシークレットの発行が
   要らない分、軽く試すには気軽(サービスプリンシパル側はアプリ登録作成 + クライアント
   シークレット/証明書の発行が別途必要)。

なお、**Agents serviceはAPIキー認証に非対応**(Entra ID必須)。「RBACの手間を省きたいから
キー認証にする」という回避はできない
([Authentication and authorization in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/concepts/authentication-authorization-foundry)
のFeature support matrix参照)。

本番でWebアプリ等から呼ぶ場合は、Agentの作成・更新は事前(デプロイ時やCI/CD)に済ませておき、
実行時に`agent_reference`で参照するだけにするのが基本。その用途ならAgent作成権限は不要で、
呼び出し元(マネージドID/サービスプリンシパル)には最小権限の**Foundry Agent Consumer**
ロールだけを割り当てればよい。

## 5. 実行して認可する

Agentを実行すると、初回はレスポンスに `oauth_consent_request` が含まれる。

`consent_link` をブラウザで開いてサインイン・同意する(この操作はFoundryのAgent
runtimeを経由しないので、consent時のアクセス元IPはAgent runtime側の固定IPとは
一致しない。詳細は [tips/mcp-oauth.md](tips/mcp-oauth.md) 参照)。

同意後、`previous_response_id` に元のレスポンスIDを指定して同じ入力を再送すると、
ツール呼び出しが実行される。一度同意すれば、同じユーザー・同じツールの組み合わせでは
以降consent不要。

上記4・5をまとめて実行するスクリプトが
[scripts/run-mcp-agent.py](../scripts/run-mcp-agent.py)。設定値は`scripts/.env`
([scripts/.env.example](../scripts/.env.example)参照)から読むので、埋めておけば
引数無しで実行できる。初回実行でconsent_linkが表示されたら同意し、表示された
`--previous-response-id`を指定して再実行する。

```bash
cd scripts
uv run ./run-mcp-agent.py
# 同意後
uv run ./run-mcp-agent.py --previous-response-id <resp_...>
```

## 6. 動作確認

- MCPサーバー側のアクセスログを確認し、ツール呼び出し時の送信元IPが期待通りか確認する
- 別のユーザーで実行し、そのユーザー分の`oauth_consent_request`が個別に発行されることを
  確認する(OAuth identity passthroughはユーザーごとにconsentが必要)
