#!/usr/bin/env bash
# Registers the Database Tools MCP Server in OpenHuman via the core's JSON-RPC.
# Usage: 03-register-mcp.sh /path/to/tokens.tok   (Personal Access Token file
# downloaded from the identity domain console: My profile -> Tokens and keys ->
# My access tokens -> Invokes other APIs -> select the MCP server app)
source "$(dirname "$0")/lib.sh"
TOKEN_FILE="${1:?personal access token file}"
PAT=$(jq -r '.app_access_token // .access_token // empty' "$TOKEN_FILE" 2>/dev/null || true)
[ -n "$PAT" ] || PAT=$(tr -d '\n' < "$TOKEN_FILE")

RPC_URL="$(tfout core_rpc_url)"
ENDPOINT="$(tfjson mcp_server | jq -r '.endpoints[0].endpoint')"
CORE_TOKEN=$(oci secrets secret-bundle get --secret-id "$(tfjson secret_ids | jq -r .core_token)" \
   --profile "$PROFILE" --region "$HOME_REGION" --query 'data."secret-bundle-content".content' --raw-output | base64 -d)

SCHEMA_URL="${RPC_URL%/rpc}/schema"
METHOD=$(curl -fsS "$SCHEMA_URL" | jq -r '[.. | strings | select(test("mcp_clients.*config.*set"))][0] // empty')
METHOD="${METHOD:-openhuman.mcp_clients_config_set}"
echo "using RPC method: $METHOD"

DOC=$(jq -n --arg url "$ENDPOINT" --arg auth "Bearer $PAT" \
  '{mcpServers: {"oracle-db": {url: $url, headers: {Authorization: $auth}}}}')

curl -fsS -X POST "$RPC_URL" -H "Authorization: Bearer $CORE_TOKEN" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg m "$METHOD" --argjson doc "$DOC" '{jsonrpc:"2.0", id:1, method:$m, params:{document:$doc}}')" | jq .
unset PAT CORE_TOKEN
