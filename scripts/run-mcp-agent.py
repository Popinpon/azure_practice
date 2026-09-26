#!/usr/bin/env python3
"""docs/mcp-foundry-setup.md の手順4(Agentにツールを追加する)と手順5(実行して
認可する)を実行する。

前提: 手順1〜3(OAuthクライアント登録・Foundry Portalでのカスタム OAuth 接続作成・
OAuthプロバイダー側へのredirect URL登録)が完了していること。MCP_CONNECTION_ID には
手順2で作成したconnectionの project_connection_id を指定する。

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

from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from dotenv import load_dotenv
from openai import AzureOpenAI

load_dotenv()


def build_client(endpoint: str, api_version: str) -> AzureOpenAI:
    token_provider = get_bearer_token_provider(
        DefaultAzureCredential(), "https://ai.azure.com/.default"
    )
    return AzureOpenAI(
        azure_endpoint=endpoint,
        api_version=api_version,
        azure_ad_token_provider=token_provider,
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
        "--api-version", default=os.environ.get("FOUNDRY_API_VERSION", "2026-08-01-preview")
    )
    parser.add_argument(
        "--model",
        default=os.environ.get("FOUNDRY_MODEL", "gpt-6-luna"),
        help="デプロイ済みモデル名。未指定なら.envのFOUNDRY_MODEL(既定 gpt-6-luna)を使う",
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
        help="Foundry Portalで作成したCustom OAuth接続のproject_connection_id。"
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
    client = build_client(args.endpoint, args.api_version)

    tools = [
        {
            "type": "mcp",
            "server_label": args.server_label,
            "server_url": args.server_url,
            "project_connection_id": args.connection_id,
            "require_approval": args.require_approval,
        }
    ]

    create_kwargs = {"model": args.model, "input": args.input, "tools": tools}
    if args.previous_response_id:
        create_kwargs["previous_response_id"] = args.previous_response_id

    response = client.responses.create(**create_kwargs)

    consent_requests = [
        item for item in response.output if item.type == "oauth_consent_request"
    ]
    if consent_requests:
        print(f"response id: {response.id}")
        for item in consent_requests:
            print(f"認可してください: {item.consent_link}")
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
