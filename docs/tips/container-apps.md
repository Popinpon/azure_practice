# Azure Container Apps 運用のTips

検証用MCPサーバー(Container Apps)側で、実際の送信元IPを確認しようとした際に
分かったハマりどころをまとめる。AgentからMCPサーバーへのOAuth接続自体のTipsは
[mcp-oauth.md](mcp-oauth.md)を参照。

### アプリのコンソールログ(Log stream)に出るIPは、実際のクライアントIPではない

Container Appの**ログ ストリーム**でアプリのstdoutを見ると、以下のようなアクセス
ログが出る(uvicorn/FastAPIなどASGIサーバーのデフォルトのアクセスログ)。

```
INFO:     100.100.0.212:40166 - "POST /mcp HTTP/1.1" 200 OK
```

この`100.100.0.212`のようなIP(`100.64.0.0/10`の範囲)は、**Container Apps内部の
共有アドレス空間**であり、実際の外部クライアントのIPではない。Ingress(Envoy
プロキシ)からアプリコンテナへの内部接続のIPをアプリがそのままログに出しているだけ。

外部の実際のクライアントIPを知るには、アプリが`X-Forwarded-For`ヘッダーを明示的に
読んでログに出す必要がある(アプリ側で対応していなければ、この方法では分からない)。

### HTTPログ(送信元IP付き)を有効にする手順

Container Apps**環境**のリソースで、左メニューの**監視 → ログ オプション**を開く。

1. 「ログの出力先」で既定は**Azure Log Analytics**(ワークスペースに送るだけの簡易
   モードで、ログの種類を選べない)になっている。**Azure Monitor**に切り替える
   (「選択した場合は、[診断設定] でログを1つ以上の宛先にルーティ...」という説明が出る)
2. 切り替えると**診断設定**の画面が出るので、ログカテゴリで**Container App HTTP logs**
   にチェックを入れて保存する
3. 「JSON ログを列に解析する」にもチェックを入れておく(入れないと、後述の`XForwardedFor`
   のような列に分解されず、生のJSONを自分でパースする必要が出る)

有効化してから数分(+ 有効化した**後**に発生したリクエストのみ記録される)経つと、
Log Analyticsに`ContainerAppHTTPLogs`テーブルが使えるようになる。

```kusto
ContainerAppHTTPLogs
| where TimeGenerated > ago(1h)
| where ContainerAppName == "<Container App名>"
| project TimeGenerated, XForwardedFor, Method, Path, StatusCode, UserAgent
| order by TimeGenerated desc
```

Foundry Agentからのリクエストは`UserAgent`が`AzureAIFoundryAgentRuntime/...`に
なっているので、それで絞り込める。

クエリを実行する画面は、Container App個別の「ログ」ブレード(スコープ付きビュー)
だと反映が遅れることがあった。反映されない場合は、Log Analyticsワークスペース
自体のリソースを直接開いて、そちらの「ログ」からクエリすると確実。

### `XForwardedFor`は複数IPのチェーンになる — 見るべきは末尾

```
100.100.209.6,100.64.17.126,20.78.16.31
```

のように、カンマ区切りで複数のIPが入ることがある。`X-Forwarded-For`は経由する
プロキシごとに末尾へ追記していく仕様なので、

- 先頭〜中間の`100.64.0.0/10`のIP群 → Azure内部(Foundry Agent runtime内部などの
  中間ホップ)
- **末尾のIP** → Container Apps Ingressが直接観測した、一番手前の送信元IP

このリポジトリの検証(送信元IP固定)では、末尾のIPが`terraform output
nat_gateway_public_ip`と一致するかを確認すればよい。

### (補足) ログを見なくても、IP制限自体で検証できる

HTTPログの設定が面倒な場合は、Container App自体にIP制限(access restriction)を
かけて、NAT Gateway以外からのアクセスを拒否させる方法でも同じことを検証できる。
具体的な手順とコマンドは[../DEPLOY.md](../DEPLOY.md)の「動作確認」節を参照。
