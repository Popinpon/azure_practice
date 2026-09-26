# AI Foundry認証まわりのTips

Foundry Agent Service自体の認証方式(Entra ID / APIキー)について、公式ドキュメントの
記載と実機の挙動が食い違っていた点をまとめる。MCPサーバー側のOAuth接続のTipsは
[mcp-oauth.md](mcp-oauth.md)を参照。

### 公式ドキュメントは「Agents serviceはAPIキー非対応」としているが、実機では通る

[Authentication and authorization in Microsoft Foundry](https://learn.microsoft.com/en-us/azure/foundry/concepts/authentication-authorization-foundry)
のFeature support matrixには、以下のように明記されている。

| Capability | API key | Microsoft Entra ID |
| --- | --- | --- |
| Agents service | No | Yes |

しかし実際に、Cognitive Servicesアカウントのキー(`az cognitiveservices account
keys list`で取得できるもの)を使って、素の`openai.OpenAI`クライアント
(`AzureOpenAI`/`AIProjectClient`ではなく)で`responses.create()`を叩いたところ、
**プロジェクトスコープのエンドポイントでは、MCPツール呼び出しまで含めて完全に成功した**
(`project_connection_id`は使わず、`tools=[{"type": "mcp", ...}]`のinline指定で
`authorization`に本物のMCPサーバー向けトークンを直接渡す方式。詳細は
[mcp-oauth.md](mcp-oauth.md)参照)。

- **プロジェクトスコープのエンドポイント**(`/api/projects/<project>/openai/v1`)+
  キー認証 + ツール無し → 成功
- 同上 + inline MCPツール + **本物のMCPトークン** → **完全成功**。`mcp_list_tools` →
  `mcp_call`(実際のツール実行・応答)→ 最終メッセージまで一気通貫で動いた
- **アカウントレベルのエンドポイント**(`/openai/v1`、project無し)+ キー認証 +
  ツール無し → 成功
- 同上 + inline MCPツール(ダミートークン・本物のMCPトークンどちらでも同じ)→
  **常に失敗**する。`{"type": "external_connector_error", "message": "Server
  returned 424: None"}`という簡素なエラーで、**トークンの有効性に関係なく同じ
  エラーになる**ことから、account-levelのMCPツール処理経路自体に何らかの問題
  (または単に未対応)がある可能性が高い

つまり結論として、**プロジェクトスコープのエンドポイントに限れば、キー認証だけで
MCPツール呼び出しが完全に動く**ことが実証できた。account-levelは素のモデル呼び出し
はキー認証で通るが、MCPツールは(理由不明だが)機能しない。

検証コード: `scripts/test_key_auth.py`(使い捨て検証用)。

**注意点**:

- 試したのは`AIProjectClient`(Entra ID必須)経由の`agents.create_version`/
  `agent_reference`方式ではなく、素の`OpenAI`クライアント + inline `tools`方式のみ。
  `project_connection_id`を使うOAuth Identity Passthrough方式や、Agentオブジェクトを
  介した`agent_reference`方式でキー認証が通るかは未確認
- 公式ドキュメントと実機が食い違っているケースなので、**将来のアップデートで
  塞がれる可能性がある**(意図しない抜け穴だった可能性も否定できない)。本番での
  利用を前提にするなら、この挙動に依存しすぎず、Entra ID認証を基本線にしておく方が
  安全

litellm経由で同じ検証をした結果は[litellm.md](litellm.md)を参照。
