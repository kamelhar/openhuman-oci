#!/usr/bin/env bash
# Scripted showcase for recording. Talks to the deployed core through the load
# balancer only. Secrets are read from Vault at runtime and never printed.
# Usage: deploy/scripts/demo.sh            (set DEMO_FAST=1 to skip pauses)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"   # recorders start a bare shell
source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$HERE/../.." && pwd)"
# Defaults for recording: tool-call evidence via the bastion tunnel if it is up, timing file for trimming.
if [ -z "${DEMO_SSH_PORT:-}" ] && nc -z 127.0.0.1 2222 2>/dev/null; then DEMO_SSH_PORT=2222; fi
DEMO_TIMING_FILE="${DEMO_TIMING_FILE:-$ROOT/media/.demo-elapsed}"
B=$'\e[1m'; D=$'\e[2m'; G=$'\e[32m'; C=$'\e[36m'; Y=$'\e[33m'; R=$'\e[0m'
pause() { [ -n "${DEMO_FAST:-}" ] || sleep "${1:-2}"; }
say()   { printf "\n%s%s%s\n" "$B$C" "$*" "$R"; }
dim()   { printf "%s%s%s\n" "$D" "$*" "$R"; }
rpc()   { curl -s --max-time 600 --cacert "$CA" -X POST "https://$LB/rpc" -H "Authorization: Bearer $TOKEN" \
          -H 'Content-Type: application/json' -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"$1\",\"params\":$2}"; }
answer(){ python3 -c 'import sys,json; d=json.load(sys.stdin); r=d.get("result"); print(r.get("result") if isinstance(r,dict) else json.dumps(d)[:600])'; }
evidence() { # last turn's tool-call count from the core log, when a bastion tunnel is up (DEMO_SSH_PORT)
  [ -n "${DEMO_SSH_PORT:-}" ] || return 0
  ssh -q -p "$DEMO_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR ubuntu@127.0.0.1 \
    'sudo docker logs --since 5m openhuman-core 2>&1 | grep "turn prompt summary" | tail -1 | grep -oE "model_calls=[0-9]+ tool_calls=[0-9]+"' 2>/dev/null \
    | sed -E 's/model_calls=([0-9]+) tool_calls=([0-9]+)/   core log: \1 model calls, \2 tool calls/'
}
turn()  { # $1 thread  $2 shown prompt  $3 full instruction  [$4 expected regex]
  local t0=$SECONDS out attempt=1
  printf "%s▶ %s%s\n" "$Y" "$2" "$R"
  while :; do
    out=$(rpc openhuman.inference_agent_chat "$(jq -n --arg m "$3" --arg t "$1-$attempt" '{message:$m, thread_id:$t}')" | answer)
    if [ -z "${4:-}" ] || printf "%s" "$out" | grep -qE "$4" || [ "$attempt" -ge 2 ]; then break; fi
    attempt=$((attempt+1))   # the prompt-guided tool dialect occasionally narrates instead of calling; one retry
  done
  printf "%s\n" "$out" | fold -s -w 110
  dim "⏱ $((SECONDS - t0))s · $MODEL via OCI Generative AI · SearXNG · Playwright MCP · memory$(evidence)"
}

DEMO_T0=$SECONDS
clear
say "OpenHuman on OCI · headless personal agent · no vendor account"
cat "$ROOT/media/architecture.txt"
# fetch endpoint, CA and token while the viewer reads the diagram
LB="$(tfout lb_public_ip)"; CA="$(mktemp)"; tfout lb_ca_certificate_pem > "$CA"
TOKEN=$(oci secrets secret-bundle get --secret-id "$(tfjson secret_ids | jq -r .core_token)" \
  --profile "$PROFILE" --region "$HOME_REGION" --query 'data."secret-bundle-content".content' --raw-output | base64 -d)
MODEL="$(tfjson genai | jq -r .chat_model)"
pause 3

say "1 · The edge: only three paths reach the core, and only with the bearer token"
printf "GET  /health            → "; curl -s --cacert "$CA" -o /dev/null -w "%{http_code}\n" "https://$LB/health"
printf "POST /rpc  (no token)   → "; curl -s --cacert "$CA" -o /dev/null -w "%{http_code}\n" -X POST "https://$LB/rpc" -d '{}'
printf "GET  /ws/dictation      → "; curl -s --cacert "$CA" -o /dev/null -w "%{http_code}\n" "https://$LB/ws/dictation"
printf "POST /rpc  (with token) → "; rpc openhuman.inference_agent_chat_simple '{"message":"Reply with exactly: core online on OCI"}' | answer
pause 3

say "2 · Web navigation: a headless browser the agent drives through MCP"
turn "demo-nav-$RANDOM" \
  "Open oracle.com/mcp in the browser, take a screenshot, and list the MCP servers Oracle offers for its database." \
  'Execute these steps now without narrating them. Step 1: call tool_search with query "browser navigate screenshot snapshot". Step 2: call browser_navigate with arguments {"url":"https://www.oracle.com/mcp/"}. Step 3: call browser_take_screenshot with arguments {"filename":"oracle-mcp.png","type":"png"}. Step 4: call browser_snapshot with arguments {}. Step 5: reply with the list of MCP servers Oracle offers for its database, one line each, nothing else.' \
  'SQLcl|Database Tools'
pause 3

say "3 · Deep research: search the web, read the sources, remember the facts"
turn "demo-research-$RANDOM" \
  "Research brief: what did Oracle ship in 2026 for agents on Oracle Database? Search, read two authoritative pages, remember the key facts, cite your sources." \
  'Execute now, do not narrate. Step 1: call web_search_tool with query "Oracle Autonomous AI Database MCP Server announcement 2026". Step 2: call web_fetch on the two most authoritative result URLs (prefer oracle.com and docs.oracle.com; if a fetch returns 403, pick the next result). Step 3: call memory_store with topic oracle-agents and a note of the 5 key facts with their URLs. Step 4: reply with exactly: a headline, 4 bullets, a Sources list of the URLs you fetched, and the line MEMORY_SAVED.' \
  'MEMORY_SAVED'
pause 3

say "4 · Memory: what the agent stored is there for next time"
printf "%s▶ %s%s\n" "$Y" "What does your memory hold about Oracle's MCP servers?" "$R"
t0=$SECONDS
rec=$(rpc openhuman.inference_agent_chat "$(jq -n --arg t "demo-recall-$RANDOM" '{thread_id:$t, message:"Call memory_recall with arguments {\"query\":\"Oracle Autonomous AI Database MCP Server\",\"limit\":5}. Answer in two sentences using only what it returned and list the URLs it contains. If it returned nothing, reply exactly MEMORY_EMPTY."}')" | answer)
if printf "%s" "$rec" | grep -q MEMORY_EMPTY; then
  dim "semantic recall is still indexing; reading the stored note directly from the memory tree:"
  rpc openhuman.memory_recall_memories '{"namespace":"global","limit":1}' \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); m=(d.get("result",{}).get("data",{}).get("memories") or [{}])[0]; print(m.get("content","")[:900])' | fold -s -w 110
else
  printf "%s\n" "$rec" | fold -s -w 110
fi
dim "⏱ $((SECONDS - t0))s · stored by the research turn via memory_store · Ollama bge-m3 embeddings on the VM"
pause 2

if oci secrets secret-bundle get --secret-id "$(tfjson secret_ids | jq -r .mcp_user_token)" --profile "$PROFILE" --region "$HOME_REGION" \
     --query 'data."secret-bundle-content".content' --raw-output 2>/dev/null | base64 -d | grep -qv '^PENDING$'; then
  say "5 · Oracle Database through the managed MCP server, under IAM roles"
  turn "demo-db-$RANDOM" \
    "Query the ORDERS table through the managed MCP server: orders per status and the biggest customer, then check the web for news about that customer." \
    'Execute now, do not narrate. Step 1: call tool_search with query "oracle-db execute sql". Step 2: call the oracle-db execute-sql tool with: select status, count(*) from orders group by status. Step 3: call it again with: select customer, sum(quantity*unit_price) total from orders group by customer order by total desc fetch first 1 rows only. Step 4: call web_search_tool for news about that customer this week. Step 5: reply with the two query results as short tables and 2 bullets on the news, nothing else.'
else
  say "5 · Oracle Database through the managed MCP server (user token pending)"
  oci dbtools mcp-server get --mcp-server-id "$(tfjson mcp_server | jq -r .id)" --profile "$PROFILE" --region "$HOME_REGION" \
     --query 'data.{name:"display-name",state:"lifecycle-state","runtime-identity":"runtime-identity"}' --output table 2>/dev/null | tail -4
fi
pause 2
say "DEMO_DONE · github.com/kamelhar/openhuman-oci"
[ -n "${DEMO_TIMING_FILE:-}" ] && echo $((SECONDS - DEMO_T0)) > "$DEMO_TIMING_FILE"
rm -f "$CA"; unset TOKEN
