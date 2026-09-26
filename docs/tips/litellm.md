# litellmでAzure AI Foundryを叩く際のTips

[foundry-auth.md](foundry-auth.md)で検証した「project-scopedエンドポイント + キー認証 +
inline MCPツール」の組み合わせが、素の`OpenAI`クライアントではなくlitellm経由でも
再現できるか検証した。

### 安定版(`1.102.1`など)ではproject-scopedのResponses APIルーティングが壊れている

litellmが内部で`responses()`呼び出しをchat completionsブリッジにフォールバックし、
project-scopedとは別物のエンドポイント(`/api/projects/<project>/models/chat/completions`、
Azure AI Foundryのモデルカタログ推論API)を叩きに行ってしまい、`api-version`必須の
エラーで失敗する。

- **account-levelのエンドポイント**(project無し)であれば`1.102.1`でも
  ネイティブ`/openai/v1/responses`に正しくルーティングされ成功する
- **project-scopedのエンドポイント**は`1.102.1`以下ではどのバージョンでも失敗する

### 修正はdev/rcビルドにしか入っていない

この不具合の修正PR([BerriAI/litellm#33856](https://github.com/BerriAI/litellm/pull/33856)、
2026-09-17にmainへマージ)はまだ安定版に降りてきていない。**dev/rcビルド
(`1.103.0rc1`以降)でようやくproject-scopedのネイティブルーティングが直る**。

- PyPIのdev/rcビルドにはmacOS arm64向けのprebuilt wheelがちゃんと用意されているので、
  `uv pip install litellm==1.104.0.dev2`のようにPyPI上のバージョンを直接指定すれば、
  普通のインストール同様すぐ終わる(数秒)
- 一方`git+https://github.com/BerriAI/litellm.git@main`のようにgit直指定でインストール
  すると、litellmのRustネイティブ拡張(`litellm-rust`。AWS SDKやtokio/rustlsなどを含む)を
  **ソースからコンパイルする**ことになり、数分〜かかる。PyPIのプレリリースで足りるなら
  git直指定は避けた方がいい

### リリース日と機能の新しさは一致しない

litellmは`1.98.x`〜`1.102.x`など複数の安定ブランチを並行メンテしてパッチを
バックポートしているため、**リリース日が新しくても機能的には古いバージョンのまま、
ということがある**。例えば`1.100.3`はリリース日こそ`1.103.0rc1`(2026-09-20)より新しい
2026-09-25だが、機能的には`1.100系`止まりで、project-scopedはおろかaccount-levelの
Responses APIすら失敗する。バージョンを選ぶときは日付ではなく**バージョン番号(と実際の
挙動)**で判断する必要がある。

### `litellm==1.104.0.dev2`での実機検証結果

`scripts/test_litellm_key_auth.py`(`scripts/test_key_auth.py`のlitellm版)を実行し、
project-scoped + inline MCPツール + 本物のMCPトークンで、`mcp_list_tools` →
`mcp_call`(実際のツール実行・応答)→ 最終メッセージまで完全成功を確認した。

account-levelは素の`OpenAI`クライアントと同じ`{"type": "external_connector_error",
"message": "Server returned 424: None"}`で失敗し、結果が一致した。これはAzure側の
制約(MCPサーバーへの接続許可がproject単位で紐づいているなど)であって、litellm固有の
問題ではないことの裏付けになる。

### 依存関係の注意: litellmと`azure-ai-projects`は同じ依存関係セットで共存できない

litellmは**全バージョンが`openai<3.0.0`を要求する**(openai SDK`v3.0.0`でのhttpx2移行に
まだ追従できていないため。[BerriAI/litellm#37907](https://github.com/BerriAI/litellm/issues/37907)
で対応中)。一方`azure-ai-projects>=2.5.0`は`openai>=3.0.0`を要求するため、**litellmと
最新のazure-ai-projectsは同じ依存関係解決の中に同時には入れられない**。

これに対応するため、`pyproject.toml`ではuvの`[tool.uv] conflicts`機能を使って
`core`(普段の実行用。`azure-ai-projects` + `openai>=3.19.2`)と`litellm`(検証用。
`litellm==1.104.0.dev2`。litellmが引っ張るopenaiは自動的に`<3.0.0`側にフォークされる)を
互いに矛盾するoptional-dependenciesとして宣言している。1つの`pyproject.toml`/`uv.lock`の
中に両方の解決結果を保持できるが、`.venv`は同時に片方の状態にしかならないので、
用途に応じて切り替える。

```sh
# 普段の実行用(run-mcp-agent.pyなど)に戻す
uv sync --extra core

# litellm検証用に切り替える
uv sync --extra litellm
uv run scripts/test_litellm_key_auth.py
```

litellm検証が終わったら`uv sync --extra core`に戻すのを忘れないこと。

検証コード: `scripts/test_litellm_key_auth.py`(使い捨て検証用)。
