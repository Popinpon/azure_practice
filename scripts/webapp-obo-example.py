#!/usr/bin/env python3
"""OBOでFoundry Agentをユーザーごとの権限で呼ぶコアロジックのサンプル。

このリポジトリの検証(terraform一式)とは無関係の、別プロジェクト(Webアプリ)向けの
参考実装。ユーザーのアクセストークン(App ServiceならEasy Authの
X-MS-TOKEN-AAD-ACCESS-TOKENヘッダーなどから取得済みの前提)を受け取り、それを
OnBehalfOfCredentialでOBO交換して、そのユーザー本人の委任された権限でAgentを呼ぶ。

流れ:
1. ユーザーのアクセストークン(user_token。audienceはこのアプリ自身)を受け取る
2. OnBehalfOfCredentialで、そのトークンをuser_assertionとしてOBO交換し、
   Foundry呼び出し用のcredentialを得る
3. そのcredentialでAIProjectClientを作り、ユーザー本人の委任された権限でAgentを呼ぶ
   (Agent自体は事前に管理者権限で作成・公開済みのものをagent_referenceで参照する
   想定。ここではcreate_versionはしない。それには別途Foundry Userロールが要る)

依存: pip install azure-identity azure-ai-projects
"""

import os

from azure.ai.projects import AIProjectClient
from azure.identity import OnBehalfOfCredential

TENANT_ID = os.environ["AZURE_TENANT_ID"]
CLIENT_ID = os.environ["AZURE_CLIENT_ID"]  # このアプリ自身のapp registration
CLIENT_SECRET = os.environ["AZURE_CLIENT_SECRET"]  # 同上(本番はFICを推奨)
FOUNDRY_PROJECT_ENDPOINT = os.environ["FOUNDRY_PROJECT_ENDPOINT"]
AGENT_NAME = os.environ.get("FOUNDRY_AGENT_NAME", "shinkansen-agent")


def call_agent_as_user(user_token: str, user_input: str) -> dict:
    """user_token(このアプリ自身をaudienceとするユーザーのアクセストークン)をOBO交換し、
    そのユーザー本人の権限でAgentを呼ぶ。"""
    obo_credential = OnBehalfOfCredential(
        tenant_id=TENANT_ID,
        client_id=CLIENT_ID,
        client_secret=CLIENT_SECRET,
        user_assertion=user_token,
    )
    project = AIProjectClient(
        endpoint=FOUNDRY_PROJECT_ENDPOINT,
        credential=obo_credential,
        allow_preview=True,
    )
    openai_client = project.get_openai_client()

    response = openai_client.responses.create(
        input=user_input,
        extra_body={"agent_reference": {"name": AGENT_NAME, "type": "agent_reference"}},
    )

    consent_requests = [
        item for item in response.output if item.type == "oauth_consent_request"
    ]
    if consent_requests:
        # このユーザーがまだMCPサーバー側の認可を済ませていない場合。
        # consent_linkをフロントエンドに返し、ユーザー自身に開いてもらう。
        return {
            "needs_consent": True,
            "consent_link": consent_requests[0].consent_link,
            "response_id": response.id,
        }

    return {"response_id": response.id, "output_text": response.output_text}
