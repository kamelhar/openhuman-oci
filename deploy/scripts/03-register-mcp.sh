#!/usr/bin/env bash
# Registers the Database Tools MCP Server in OpenHuman via the core's JSON-RPC.
# Usage: 03-register-mcp.sh /path/to/tokens.tok   (Personal Access Token file
# downloaded from the identity domain console: My profile -> Tokens and keys ->
# My access tokens -> Invokes other APIs -> select the MCP server app)
source "$(dirname "$0")/lib.sh"
TOKEN_FILE="${1:?personal access token file}"
PAT=$(jq -r '.app_access_token // .access_token // empty' "$TOKEN_FILE" 2>/dev/null || true)
[ -n "$PAT" ] || PAT=$(tr -d '\n' < "$TOKEN_FILE")

if [ "${2:-}" != "--direct" ]; then
  SECRET_ID=$(tfjson secret_ids | jq -r .mcp_user_token)
  oci vault secret update-base64 --secret-id "$SECRET_ID" --secret-content-content "$(printf %s "$PAT" | base64)" \
     --profile "$PROFILE" --region "$HOME_REGION" >/dev/null
  unset PAT
  echo "token stored in Vault; the VM registers the MCP server within ~2 minutes (openhuman-render.timer)."
  exit 0
fi

RPC_URL="$(tfout core_rpc_url)"
ENDPOINT="$(tfjson mcp_server | jq -r '.endpoints[0].endpoint')"
CORE_TOKEN=$(oci secrets secret-bundle get --secret-id "$(tfjson secret_ids | jq -r .core_token)" \
   --profile "$PROFILE" --region "$HOME_REGION" --query 'data."secret-bundle-content".content' --raw-output | base64 -d)

METHOD="openhuman.mcp_clients_config_set"

PARAMS=$(jq -n --arg url "$ENDPOINT" --arg auth "Bearer $PAT" \
  '{mcpServers: {"oracle-db": {url: $url, headers: {Authorization: $auth}, description: "Oracle AI Database via OCI Database Tools MCP Server"}}}')

CA=$(mktemp); tfout lb_ca_certificate_pem > "$CA"
curl -fsS --cacert "$CA" -X POST "$RPC_URL" -H "Authorization: Bearer $CORE_TOKEN" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg m "$METHOD" --argjson p "$PARAMS" '{jsonrpc:"2.0", id:1, method:$m, params:$p}')" | jq .
rm -f "$CA"
unset PAT CORE_TOKEN
