#!/usr/bin/env python3
"""Agentを作成せず(`create_version`無し)、`responses.create()`に`tools`を直接渡して
MCPサーバーを呼ぶ。`run-mcp-agent-direct-token.py`と同じく`project_connection_id`は
使わず`MCPTool.authorization`にトークンを直接渡す方式だが、こちらはAgentオブジェクト
自体を作らない、より薄い呼び方。

これは「Agentを介さない呼び方でも、送信元IPはNAT Gateway経由(=snet-agentの
Agent runtime)になるか」を確認する目的で作った(docs/tips/mcp-oauth.md参照)。
実機では動作自体は成功したが、送信元IPがAgent経由の場合と同じになるかは
別途Container AppsのHTTPログ(XForwardedFor)で確認すること。

依存: pip install msal azure-identity azure-ai-projects python-dotenv

使い方 (uv sync 済み、scripts/ ディレクトリで実行すること):
  cd scripts
  uv run ./run-mcp-inline-tools.py
"""

import argparse
import os
import sys

import msal
from azure.ai.projects import AIProjectClient
from azure.identity import DefaultAzureCredential
from dotenv import load_dotenv

load_dotenv()


def get_mcp_token(tenant_id: str, client_id: str, scope: str) -> str:
    """MCPサーバー向けのアクセストークンを、デバイスコードフローで取得する。"""
    app = msal.PublicClientApplication(
        client_id, authority=f"https://login.microsoftonline.com/{tenant_id}"
    )
    flow = app.initiate_device_flow(scopes=[scope])
    if "user_code" not in flow:
        raise RuntimeError(f"デバイスコードフローの開始に失敗: {flow}")
    print(flow["message"])
    result = app.acquire_token_by_device_flow(flow)
    if "access_token" not in result:
        raise RuntimeError(f"トークン取得に失敗: {result}")
    return result["access_token"]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--endpoint", default=os.environ.get("FOUNDRY_ENDPOINT", ""))
    parser.add_argument(
        "--project", default=os.environ.get("FOUNDRY_PROJECT", "closed-project")
    )
    parser.add_argument("--model", default=os.environ.get("FOUNDRY_MODEL", "gpt-5.6-luna"))
    parser.add_argument(
        "--server-label", default=os.environ.get("MCP_SERVER_LABEL", "shinkansen")
    )
    parser.add_argument("--server-url", default=os.environ.get("TF_VAR_mcp_server_url", ""))
    parser.add_argument("--mcp-tenant-id", default=os.environ.get("MCP_TENANT_ID", ""))
    parser.add_argument("--mcp-client-id", default=os.environ.get("MCP_CLIENT_ID", ""))
    parser.add_argument("--mcp-scope", default=os.environ.get("MCP_SCOPE", ""))
    parser.add_argument(
        "--input",
        default=os.environ.get(
            "AGENT_INPUT", "MCPサーバーで使えるツールを一覧して、1つ試しに呼び出してください。"
        ),
    )
    args = parser.parse_args()

    missing = [
        env_name
        for value, env_name in [
            (args.endpoint, "FOUNDRY_ENDPOINT (--endpoint)"),
            (args.server_url, "TF_VAR_mcp_server_url (--server-url)"),
            (args.mcp_tenant_id, "MCP_TENANT_ID (--mcp-tenant-id)"),
            (args.mcp_client_id, "MCP_CLIENT_ID (--mcp-client-id)"),
            (args.mcp_scope, "MCP_SCOPE (--mcp-scope)"),
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

    print("MCPサーバー向けトークンを取得します(デバイスコードフロー)...")
    mcp_token = get_mcp_token(args.mcp_tenant_id, args.mcp_client_id, args.mcp_scope)
    print("トークン取得完了。")

    project_endpoint = args.endpoint.rstrip("/") + "/api/projects/" + args.project
    project = AIProjectClient(
        endpoint=project_endpoint,
        credential=DefaultAzureCredential(),
        allow_preview=True,
    )
    openai_client = project.get_openai_client()

    tools = [
        {
            "type": "mcp",
            "server_label": args.server_label,
            "server_url": args.server_url,
            "require_approval": "never",
            "authorization": mcp_token,
        }
    ]

    response = openai_client.responses.create(
        model=args.model,
        input=args.input,
        tools=tools,
    )

    print(f"response id: {response.id}")
    for item in response.output:
        print(f"- type={item.type}: {item}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
