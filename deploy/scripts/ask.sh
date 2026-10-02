#!/usr/bin/env bash
# One agent turn through the load balancer. Usage: ask.sh "prompt" [thread_id] [model_override]
# Prints the answer, then an elapsed line on stderr. Token and CA come from Terraform outputs and Vault.
source "$(dirname "$0")/lib.sh"
MSG="${1:?prompt}"; THREAD="${2:-ask-$RANDOM}"; MODEL="${3:-}"
LB="$(tfout lb_public_ip)"; CA="$(mktemp)"; tfout lb_ca_certificate_pem > "$CA"
TOKEN=$(oci secrets secret-bundle get --secret-id "$(tfjson secret_ids | jq -r .core_token)" \
  --profile "$PROFILE" --region "$HOME_REGION" --query 'data."secret-bundle-content".content' --raw-output | base64 -d)
PARAMS=$(jq -n --arg m "$MSG" --arg t "$THREAD" --arg mo "$MODEL" '{message:$m, thread_id:$t} + (if $mo != "" then {model_override:$mo} else {} end)')
t0=$SECONDS
curl -s --max-time 900 --cacert "$CA" -X POST "https://$LB/rpc" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d "$(jq -n --argjson p "$PARAMS" '{jsonrpc:"2.0", id:1, method:"openhuman.inference_agent_chat", params:$p}')" \
  | python3 -c 'import sys,json
raw=sys.stdin.read()
try:
    d=json.loads(raw); r=d.get("result")
    print(r.get("result") if isinstance(r,dict) else json.dumps(d)[:800])
except Exception: print("RAW:", raw[:400])'
>&2 echo "⏱ $((SECONDS - t0))s${MODEL:+ · model $MODEL}"
rm -f "$CA"; unset TOKEN
