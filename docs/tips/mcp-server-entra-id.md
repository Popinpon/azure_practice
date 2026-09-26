# MCPサーバーでEntra IDをOAuthプロバイダーにする際の注意点

自前のMCPサーバー(リソースサーバー)をEntra IDで保護する場合の、Entraアプリ登録・
トークン検証実装まわりの注意点。AI Foundry固定IP(NAT Gateway)の話とは別軸で、
**MCPサーバー自身を認可設定する側**(=MCPサーバーの運用者)の視点。Foundry側から
このMCPサーバーに接続する手順は[../mcp-foundry-setup.md](../mcp-foundry-setup.md)を参照。

## Entra IDアプリ登録の流れ

### アプリ登録を作成する

Azure Portal → **Microsoft Entra ID** → **アプリの登録** → **新規登録**。

- 名前: 任意(MCPサーバー名など)
- サポートされているアカウントの種類: 通常は「この組織ディレクトリのみ」(シングルテナント)
- リダイレクトURI: この時点では追加しなくてよい(Foundry接続時に発行される値を
  [../mcp-foundry-setup.md](../mcp-foundry-setup.md)の手順でまとめて追加する)

作成後、**アプリケーション(クライアント) ID** と **ディレクトリ(テナント) ID** を控えておく。

### クライアントシークレットを発行する(MCPサーバー側が要求する場合のみ)

クライアントシークレットが必要かどうかは、MCPサーバー(のOAuth実装)がconfidential
client(シークレットあり)とpublic client(シークレット無し・PKCEのみ)のどちらを
前提にしているかによる。[Foundryの公式ドキュメント](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/mcp-authentication)
でもCustom OAuthの`Client secret`は「optional (depends on your OAuth app)」扱いで、
一律必須ではない。MCPサーバー側のドキュメント・実装を確認し、confidential client
を要求している場合のみ以下を行う。

**証明書とシークレット** → **新しいクライアントシークレット**。

- 有効期限は運用方針に合わせて選択
- 発行直後にしか値(Value)を確認できないので、その場でコピーして安全な場所に保存する
- **「シークレット ID」と「値(Value)」を混同しない**。シークレットIDはそのシークレット
  というレコードを識別するだけのGUIDで、OAuthの認証には使えない。Foundry Portal側の
  `Client secret`欄([../mcp-foundry-setup.md](../mcp-foundry-setup.md)手順1・2)に
  入れるのは必ず値(Value)の方。シークレットIDを入れてしまうと、consent自体は通っても
  トークン交換の段階で無効なclient_secretとして弾かれる(値を控え忘れた場合は、
  シークレットを発行し直すしかない)

このシークレットの有無が、後でFoundry側にリダイレクトURIを登録する際の
プラットフォーム種別(Web / public client用)の判断基準にもなる。

### APIを公開してスコープを定義する

**API の公開** タブ。

1. Application ID URIを確認・設定する。既定値は `api://<アプリID>` で、通常はこのまま
   でよい(独自ホスト名を追加登録したい場合は次項参照)
2. **スコープの追加** で、MCPサーバーが要求するスコープ名を定義する(例: `seat.read`)
   - 同意できるユーザー: 通常は「管理者とユーザー」
   - 表示名・説明を入力

このスコープ名が、MCPクライアント(Foundryなど)の設定で使う値になる。

### プラットフォームのホスト名をidentifier URIとして追加したい場合

MCPサーバーのURL(例: `https://<container-app>.azurecontainerapps.io/mcp`)を
そのままidentifier URI(`identifierUris`)として登録したい場合、Entra IDは既定で
「テナント検証済みドメイン・テナントID・アプリIDのいずれかを含むURIしか許可しない」
制約を持っている。

ただし、アプリを **v2.0トークンを使う設定**(`api.requestedAccessTokenVersion: 2`)に
しておくと、この制約の対象から既定で除外される(テナントのアプリ管理ポリシーによる)。
スコープ追加時にv2.0トークンの設定が入っていれば該当することが多い。

テナントのポリシー状態は以下で確認できる。

```bash
az rest --method GET --uri "https://graph.microsoft.com/v1.0/policies/defaultAppManagementPolicy"
```

`uriAdditionWithoutUniqueTenantIdentifier.excludeAppsReceivingV2Tokens` が `true`
なら、v2.0トークン設定のアプリはプラットフォームホスト名でも登録できる可能性が高い。
`nonDefaultUriAddition` が有効(nullでない)なテナントでは、この除外だけでは
足りずカスタムドメインの用意が必要になる場合がある。

登録コマンド例:

```bash
az ad app update --id "$APP_ID" \
  --identifier-uris "api://$APP_ID" "https://<mcpサーバーのホスト名>/mcp"
```

### audクレームがApplication ID URIと一致しないことがある

MCPサーバーURLで修飾したスコープ名(例: `https://<host>/mcp/<scope>`)でトークンを
要求すると、発行されるトークンの `aud` クレームが `api://<アプリID>` ではなく
**`api://` プレフィックスの無い裸のアプリID(GUID)** になることがある(実機で確認済み。
Entra側の内部的なresource解決の挙動と見られ、正確な仕様は未調査)。

MCPサーバー側のトークン検証では、`api://<アプリID>` 形式と裸のGUID形式の**両方**を
許可audienceとして受け付けるようにしておくと、この挙動に関わらず正しく動作する。

### 推奨: 自分のMCPサーバーでPRM(Protected Resource Metadata)を公開する

MCPサーバー自身が `/.well-known/oauth-protected-resource/<mcpのパス>` で
`resource` / `authorization_servers` / `scopes_supported` を返すようにしておくと、

- PRM対応クライアント(Claude Desktop/Claude.aiなど)は自動でscopeを解決できる
- PRM非対応クライアント(Foundryなど、[../mcp-foundry-setup.md](../mcp-foundry-setup.md)
  参照)に設定する場合も、このエンドポイントをcurlするだけで正確な値(テナントID・
  auth/token URL・scope名)を確認でき、手入力のミスを防げる

```bash
curl -s https://<mcpサーバーのホスト名>/.well-known/oauth-protected-resource/mcp
```
