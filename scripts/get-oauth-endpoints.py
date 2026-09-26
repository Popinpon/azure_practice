#!/usr/bin/env python3
"""MCPサーバーのPRM(Protected Resource Metadata)と、その認可サーバーのdiscovery
ドキュメントから、AI FoundryのCustom OAuth設定に必要な値だけを抜き出して表示する。

PRM URLは省略可能。省略した場合はscripts/.envのTF_VAR_mcp_server_url
(例: https://<host>/mcp)から `https://<host>/.well-known/oauth-protected-resource/mcp`
を自動で組み立てる。.envの用意は scripts/.env.example を参照。

使い方 (uv sync 済み、scripts/ ディレクトリで実行すること):
  cd scripts
  uv run ./get-oauth-endpoints.py
  # または、PRM URLを直接指定する場合
  uv run ./get-oauth-endpoints.py https://<host>/.well-known/oauth-protected-resource/mcp
"""

import json
import os
import sys
import urllib.error
import urllib.request
from urllib.parse import urlsplit, urlunsplit

from dotenv import load_dotenv

load_dotenv()


def fetch_json(url: str) -> dict:
    with urllib.request.urlopen(url) as res:
        return json.load(res)


def prm_url_from_server_url(server_url: str) -> str:
    parts = urlsplit(server_url)
    prm_path = "/.well-known/oauth-protected-resource" + (parts.path or "/")
    return urlunsplit((parts.scheme, parts.netloc, prm_path, "", ""))


def main() -> int:
    if len(sys.argv) > 2:
        print(f"使い方: {sys.argv[0]} [MCPサーバーのPRM URL]", file=sys.stderr)
        return 1

    if len(sys.argv) == 2:
        prm_url = sys.argv[1]
    else:
        server_url = os.environ.get("TF_VAR_mcp_server_url", "")
        if not server_url:
            print(
                "PRM URLが未指定で、.envのTF_VAR_mcp_server_urlも設定されていません",
                file=sys.stderr,
            )
            return 1
        prm_url = prm_url_from_server_url(server_url)

    prm = fetch_json(prm_url)
    issuer = prm["authorization_servers"][0]

    try:
        discovery = fetch_json(f"{issuer}/.well-known/openid-configuration")
    except urllib.error.HTTPError:
        print(
            f"エラー: issuerがOpenID Connectのdiscoveryに対応していません。issuer={issuer}\n"
            f"RFC 8414の {issuer}/.well-known/oauth-authorization-server を代わりに試してください。",
            file=sys.stderr,
        )
        return 1

    scopes = " ".join(prm.get("scopes_supported", []))
    print(f"server_url:  {prm['resource']}")
    print(f"Auth URL:    {discovery['authorization_endpoint']}")
    print(f"Token URL:   {discovery['token_endpoint']}")
    print(f"Refresh URL: {discovery['token_endpoint']}")
    print(f"Scopes:      {scopes} offline_access")
    return 0


if __name__ == "__main__":
    sys.exit(main())
