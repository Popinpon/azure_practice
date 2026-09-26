import os

import msal
from dotenv import load_dotenv
from openai import OpenAI

load_dotenv()

endpoint = os.environ["FOUNDRY_ENDPOINT"].rstrip("/")
project = os.environ.get("FOUNDRY_PROJECT", "closed-project")
api_key = os.environ["TEST_FOUNDRY_KEY"]
server_url = os.environ["TF_VAR_mcp_server_url"]
server_label = os.environ.get("MCP_SERVER_LABEL", "shinkansen")

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
base_url = f"{endpoint}/api/projects/{project}/openai/v1"
client = OpenAI(base_url=base_url, api_key=api_key)

try:
    response = client.responses.create(
        model="gpt-5.6-luna", input="helloツールを呼んでください", tools=tools
    )
    print("SUCCESS (project-scoped, key auth, real mcp token)")
    for item in response.output:
        print(f"- type={item.type}: {item}")
except Exception as e:
    print(f"FAILED (project-scoped, key auth, real mcp token): {type(e).__name__}: {e}")

# アカウントレベル(project無し)のエンドポイント + 本物のMCPトークン
account_base_url = f"{endpoint}/openai/v1"
account_client = OpenAI(base_url=account_base_url, api_key=api_key)

try:
    response2 = account_client.responses.create(
        model="gpt-5.6-luna", input="helloツールを呼んでください", tools=tools
    )
    print("SUCCESS (account-level, key auth, real mcp token)")
    for item in response2.output:
        print(f"- type={item.type}: {item}")
except Exception as e:
    print(f"FAILED (account-level, key auth, real mcp token): {type(e).__name__}: {e}")
