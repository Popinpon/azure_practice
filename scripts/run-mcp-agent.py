#!/usr/bin/env python3
"""docs/mcp-foundry-setup.md の手順4(Agentにツールを追加する)と手順5(実行して
認可する)を実行する。

Foundry Agent ServiceはAIProjectClient経由(project-scoped endpoint)で呼ぶ必要が
あり、Responses APIへの`tools`はAgent定義(PromptAgentDefinition)に持たせた上で
`agent_reference`で参照する形になる(公式サンプル:
https://learn.microsoft.com/azure/foundry/agents/how-to/tools/model-context-protocol )。

前提: 手順1〜3(OAuthクライアント登録・Foundry Portalでのカスタム OAuth 接続作成・
OAuthプロバイダー側へのredirect URL登録)が完了していること。MCP_CONNECTION_ID には、
Foundry Portalの対象ツール詳細画面(Build → 接続したツールを開く)の
「プロジェクト接続 ID」欄に表示されている値を指定する(公式サンプルでは短い
connection名だが、Portal上はARMリソースIDのフルパスを表示するため、うまく行かない
場合はどちらの形式も試すこと)。

設定は scripts/.env から読む。scripts/.env.example を参考に作成すること。
個別に上書きしたい値だけ、対応する --オプションで指定すればよい。

認証: az login 済みのアカウントでDefaultAzureCredentialを使う。

使い方 (uv sync 済み、scripts/ ディレクトリで実行すること):
  cd scripts

  # 初回実行。consent_linkが表示されるので、ブラウザで開いて同意する
  uv run ./run-mcp-agent.py

  # 同意後、表示された response id を指定して同じ入力を再送する
  # (このときツール呼び出しが実際に実行される)
  uv run ./run-mcp-agent.py --previous-response-id <resp_...>
"""

import argparse
import os
import sys

import openai
from azure.ai.projects import AIProjectClient
from azure.ai.projects.models import MCPTool, PromptAgentDefinition
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

load_dotenv()


def build_project_client(endpoint: str, project: str) -> AIProjectClient:
    project_endpoint = endpoint.rstrip("/") + "/api/projects/" + project
    return AIProjectClient(
        endpoint=project_endpoint,
        credential=DefaultAzureCredential(),
        allow_preview=True,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--endpoint",
        default=os.environ.get("FOUNDRY_ENDPOINT", ""),
        help="AI Foundryアカウントのエンドポイント。未指定なら.envのFOUNDRY_ENDPOINTを使う",
    )
    parser.add_argument(
        "--project",
        default=os.environ.get("FOUNDRY_PROJECT", "closed-project"),
        help="Foundryプロジェクト名。未指定なら.envのFOUNDRY_PROJECT"
        "(既定 closed-project。terraformのbase_name-projectと同じ)を使う",
    )
    parser.add_argument(
        "--model",
        default=os.environ.get("FOUNDRY_MODEL", "gpt-6-luna"),
        help="デプロイ済みモデル名。未指定なら.envのFOUNDRY_MODEL(既定 gpt-6-luna)を使う",
    )
    parser.add_argument(
        "--agent-name",
        default=os.environ.get("FOUNDRY_AGENT_NAME", "mcp-verify-agent"),
        help="作成/更新するAgent名。未指定なら.envのFOUNDRY_AGENT_NAMEを使う",
    )
    parser.add_argument(
        "--server-label",
        default=os.environ.get("MCP_SERVER_LABEL", ""),
        help="MCPツールの任意の識別名。未指定なら.envのMCP_SERVER_LABELを使う",
    )
    parser.add_argument(
        "--server-url",
        default=os.environ.get("TF_VAR_mcp_server_url", ""),
        help="MCPサーバーのエンドポイント。未指定なら.envのTF_VAR_mcp_server_urlを使う",
    )
    parser.add_argument(
        "--connection-id",
        default=os.environ.get("MCP_CONNECTION_ID", ""),
        help="Foundry Portalの「プロジェクト接続 ID」欄の値。"
        "未指定なら.envのMCP_CONNECTION_IDを使う",
    )
    parser.add_argument(
        "--require-approval",
        default=os.environ.get("MCP_REQUIRE_APPROVAL", "never"),
        choices=["never", "always"],
        help="検証用途では既定のneverでよい。本番相当の確認をしたい場合はalways",
    )
    parser.add_argument(
        "--input",
        default=os.environ.get(
            "AGENT_INPUT", "MCPサーバーで使えるツールを一覧して、1つ試しに呼び出してください。"
        ),
        help="Agentへの入力テキスト",
    )
    parser.add_argument(
        "--previous-response-id",
        default=os.environ.get("FOUNDRY_PREVIOUS_RESPONSE_ID"),
        help="手順5で認可した後、同じ入力を再送する際に指定する元のresponse id",
    )
    args = parser.parse_args()

    missing = [
        env_name
        for value, env_name in [
            (args.endpoint, "FOUNDRY_ENDPOINT (--endpoint)"),
            (args.server_label, "MCP_SERVER_LABEL (--server-label)"),
            (args.server_url, "TF_VAR_mcp_server_url (--server-url)"),
            (args.connection_id, "MCP_CONNECTION_ID (--connection-id)"),
        ]
        if not value
    ]
    if missing:
        parser.error(
            "以下の値が.envにも--オプションにも指定されていません: " + ", ".join(missing)
        )
    return args


def main() -> int:
    args = parse_args()
    project = build_project_client(args.endpoint, args.project)
    openai_client = project.get_openai_client()

    tool = MCPTool(
        server_label=args.server_label,
        server_url=args.server_url,
        require_approval=args.require_approval,
        project_connection_id=args.connection_id,
    )

    try:
        agent = project.agents.create_version(
            agent_name=args.agent_name,
            definition=PromptAgentDefinition(
                model=args.model,
                instructions="MCPサーバーのツールを必要に応じて使ってください。",
                tools=[tool],
            ),
        )
    except openai.APIStatusError as err:
        print(f"リクエストURL: {err.response.request.url}", file=sys.stderr)
        print(f"レスポンス: {err.response.text}", file=sys.stderr)
        raise
    print(f"agent: {agent.name} (version {agent.version})")

    create_kwargs = {
        "input": args.input,
        "extra_body": {"agent_reference": {"name": agent.name, "type": "agent_reference"}},
    }
    if args.previous_response_id:
        create_kwargs["previous_response_id"] = args.previous_response_id

    try:
        response = openai_client.responses.create(**create_kwargs)
    except openai.APIStatusError as err:
        print(f"リクエストURL: {err.response.request.url}", file=sys.stderr)
        print(f"レスポンス: {err.response.text}", file=sys.stderr)
        raise

    consent_requests = [
        item for item in response.output if item.type == "oauth_consent_request"
    ]
    if consent_requests:
        print(f"response id: {response.id}")
        for item in consent_requests:
            # OSC 8ハイパーリンク。VSCode等の対応ターミナルではクリック可能なリンクになる
            # (未対応ターミナルでもURL文字列自体は表示される)
            link = f"\033]8;;{item.consent_link}\033\\{item.consent_link}\033]8;;\033\\"
            print(f"認可してください: {link}")
        print(
            "\n同意後、このresponse idを--previous-response-idに指定して再実行してください:",
            file=sys.stderr,
        )
        print(f"  --previous-response-id {response.id}", file=sys.stderr)
        return 0

    print(f"response id: {response.id}")
    for item in response.output:
        print(f"- type={item.type}: {item}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
