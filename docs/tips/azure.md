# Azure運用のTips

このリポジトリを作る過程で分かった、`README.md` / `ARCHITECTURE.md` には書いていない
Azureサービス自体の挙動・運用面の知見をまとめる。Terraform/AVMモジュール周りの
ハマりどころは [terraform.md](terraform.md) を参照。

### モデルの実際の提供状況は `az cognitiveservices model list` で確認するのが確実

MS Learnのリージョン対応表はモデルのGAから数日〜数週間、更新が追いつかないことがある
(このリポジトリでも `gpt-6-luna` のリージョン対応表記が古く、実際には使えるのに
ドキュメント上は載っていないように見えるケースがあった)。デプロイ前に対象リージョンで
実際に使えるか、Azure自身に問い合わせるのが最も確実。

```bash
az cognitiveservices model list --location japaneast \
  -o json | jq '[.[] | select(.model.name == "gpt-6-luna")]'
```

### Standard Agent Setup(VNet injection込み)のアカウント作成は非常に時間がかかることがある

公式ドキュメントは「(依存リソース含む)フルプロビジョニングに30〜45分程度」としているが、
このリポジトリの検証では **AI Foundryアカウント単体の作成だけで50分以上** かかった
(依存リソースは別途先に作成済みの状態で)。エラーが出ていなくても異常とは限らないので、
`Still creating...` が続いても慌てず、Azure側の `provisioningState` を直接確認しつつ
気長に待つのが無難。

```bash
az cognitiveservices account show -g <rg> -n <name> \
  --query "properties.provisioningState" -o tsv
```

### AI SearchのServerlessは(2026年9月時点)まだ閉域構成に向かない

2026-09-13からAI SearchにServerless(Developer)ティアのプレビューが始まっているが、
以下の理由で今回のような閉域構成には使えない。

- パブリックプレビューでSLAなし、本番非推奨
- 「Private networking for indexers: 非対応」「Shared Private Link: 対応予定なし」と明記
  されており、Private Endpoint対応が明言されていない
- 他ティアとの相互移行不可
- 提供リージョンが限定的

GA後にPrivate Endpoint対応が入ったら乗り換えを検討する価値はあるが、現時点ではBasic
SKU(Dedicatedモデル)を使うしかない。
