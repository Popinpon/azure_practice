import os

import litellm
import msal
from dotenv import load_dotenv

load_dotenv()

endpoint = os.environ["FOUNDRY_ENDPOINT"].rstrip("/")
project = os.environ.get("FOUNDRY_PROJECT", "closed-project")
api_key = os.environ["TEST_FOUNDRY_KEY"]
server_url = os.environ["TF_VAR_mcp_server_url"]
server_label = os.environ.get("MCP_SERVER_LABEL", "shinkansen")

model = "azure_ai/gpt-5.6-luna"

# 本物のMCPトークンを取得(デバイスコードフロー)
mcp_tenant_id = os.environ["MCP_TENANT_ID"]
mcp_client_id = os.environ["MCP_CLIENT_ID"]
mcp_scope = os.environ["MCP_SCOPE"]

msal_app = msal.PublicClientApplication(
    mcp_client_id, authority=f"https://login.microsoftonline.com/{mcp_tenant_id}"
)
flow = msal_app.initiate_device_flow(scopes=[mcp_scope])
print(flow["message"])
result = msal_app.acquire_token_by_device_flow(flow)
mcp_token = result["access_token"]
print("MCPトークン取得完了。")

tools = [
    {
        "type": "mcp",
        "server_label": server_label,
        "server_url": server_url,
        "require_approval": "never",
        "authorization": mcp_token,
    }
]

# project-scoped endpoint, key auth + 本物のMCPトークン
# litellmのazure_aiプロバイダはproject-scopedをネイティブ/openai/v1/responsesに
# ルーティングする(1.103.0rc1以降。pyproject.tomlのlitellm==1.104.0.dev2で確認済み)
project_api_base = f"{endpoint}/api/projects/{project}"

try:
    response = litellm.responses(
        model=model,
        input="helloツールを呼んでください",
        tools=tools,
        api_key=api_key,
        api_base=project_api_base,
    )
    print("SUCCESS (project-scoped, key auth, real mcp token)")
    for item in response.output:
        print(f"- type={item.type}: {item}")
except Exception as e:
    print(f"FAILED (project-scoped, key auth, real mcp token): {type(e).__name__}: {e}")

# アカウントレベル(project無し)のエンドポイント + 本物のMCPトークン
account_api_base = endpoint

try:
    response2 = litellm.responses(
        model=model,
        input="helloツールを呼んでください",
        tools=tools,
        api_key=api_key,
        api_base=account_api_base,
    )
    print("SUCCESS (account-level, key auth, real mcp token)")
    for item in response2.output:
        print(f"- type={item.type}: {item}")
except Exception as e:
    print(f"FAILED (account-level, key auth, real mcp token): {type(e).__name__}: {e}")
