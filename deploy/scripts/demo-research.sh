#!/usr/bin/env bash
# Showcase 2: deep research on a clinical dataset. Public ClinicalTrials.gov
# registry data (no patient data) in Oracle Autonomous AI Database, then live
# web research by parallel researcher agents, a deep dive, and memory.
# Usage: deploy/scripts/demo-research.sh   (DEMO_FAST=1 skips pauses; DEMO_PACE=2 for recording)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
source "$(dirname "$0")/lib.sh"
ROOT="$(cd "$HERE/../.." && pwd)"
PY="$ROOT/.venv/bin/python"; [ -x "$PY" ] || PY=python3
if [ -z "${DEMO_SSH_PORT:-}" ] && nc -z 127.0.0.1 2222 2>/dev/null; then DEMO_SSH_PORT=2222; fi
DEMO_TIMING_FILE="${DEMO_TIMING_FILE:-$ROOT/media/.demo-research-elapsed}"
export OCI_PROFILE="$PROFILE" OCI_HOME_REGION="$HOME_REGION" PYTHONWARNINGS=ignore
B=$'\e[1m'; D=$'\e[2m'; G=$'\e[32m'; C=$'\e[36m'; Y=$'\e[33m'; R=$'\e[0m'
PACE="${DEMO_PACE:-1}"
pause()  { [ -n "${DEMO_FAST:-}" ] || sleep "$(python3 -c "print(${1:-2}*$PACE)")"; }
reveal() { if [ -n "${DEMO_FAST:-}" ]; then cat; else while IFS= read -r line; do printf "%s\n" "$line"; sleep 0.18; done; fi; }
say()    { printf "\n%s%s%s\n" "$B$C" "$*" "$R"; }
dim()    { printf "%s%s%s\n" "$D" "$*" "$R"; }
ask()    { "$HERE/ask.sh" "$1" "$2" 2>/dev/null; }
MODEL="$(tfjson genai | jq -r .chat_model)"
T="$(mktemp -d)"
DEMO_T0=$SECONDS

clear
say "OpenHuman on OCI · deep research on a clinical dataset"
cat <<'TXT' | reveal
  Data     ClinicalTrials.gov registry · 4,300 Alzheimer disease studies · public metadata, no patient data
           loaded into Oracle Autonomous AI Database 26ai (Always Free) inside the tenancy
  Agent    openhuman-core on an Ampere VM · OCI Generative AI · SearXNG · Playwright MCP · memory
  Access   agents reach the database only through the managed Database Tools MCP Server (IAM app roles)
TXT
pause 5

say "1 · The dataset: what is in the database"
dim "SQL run inside the VCN over TLS (the agent's own governed path through MCP waits for the user token)"
"$HERE/sql-vm.sh" "select phase, count(*) trials, sum(case when overall_status='RECRUITING' then 1 else 0 end) recruiting, sum(enrollment) enrolled from clinical_trials where phase in ('PHASE3','PHASE2','PHASE2,PHASE3') group by phase order by trials desc" | reveal
pause 2
dim "top industry sponsors of Phase 3 Alzheimer trials, all time"
SPONSORS_TABLE=$("$HERE/sql-vm.sh" "select lead_sponsor, count(*) trials, sum(enrollment) enrolled from clinical_trials where phase like '%PHASE3%' and sponsor_class='INDUSTRY' group by lead_sponsor order by trials desc fetch first 5 rows only")
printf "%s\n" "$SPONSORS_TABLE" | reveal
# short names for the top three, derived from the query result
mapfile -t TOP3 < <(printf "%s\n" "$SPONSORS_TABLE" | awk -F'|' 'NR>2 {gsub(/^ +| +$/,"",$2); print $2}' | head -3 | sed -E 's/^Eli Lilly.*/Eli Lilly/; s/.*Roche.*/Roche/; s/^Johnson.*/Johnson \& Johnson/; s/^Otsuka.*/Otsuka/; s/^Merck.*/Merck/; s/^Pfizer.*/Pfizer/; s/ (Inc|LLC|Ltd|Limited|Corporation|Company|AG|SA|plc)\.?$//')
dim "→ researching the top three on the live web: ${TOP3[*]}"
pause 5

say "2 · Fan-out: one researcher agent per sponsor, in parallel, on the live web"
mk() { echo "Execute now, do not narrate, exactly one tool call per message and wait for its result. Never call juice_* tools. Topic: $1 and Alzheimer disease, 2025-2026. Step 1: call web_search_tool with query \"$1 Alzheimer 2026 phase 3 approval pipeline\". Step 2: call web_fetch on the most authoritative result (sponsor site, fda.gov, nejm.org, reuters.com, fiercebiotech.com) with max_bytes 12000. Step 3: call web_fetch on a second source with max_bytes 12000 (skip 403s). Step 4: reply with exactly 3 bullets, each one verified fact ending with its source URL, nothing else."; }
t0=$SECONDS
for S in "${TOP3[@]}"; do printf "%s▶ researcher · %s%s\n" "$Y" "$S" "$R"; ( ask "$(mk "$S")" "fan-$RANDOM" > "$T/$(echo "$S" | tr ' &' '__').txt" ) & done
wait
dim "three agent turns completed in $((SECONDS - t0))s · each: web_search_tool → web_fetch ×2 → 3 sourced bullets"
for S in "${TOP3[@]}"; do F="$T/$(echo "$S" | tr ' &' '__').txt"; printf "%s%s%s\n" "$B" "$S" "$R"; fold -s -w 110 "$F" | reveal; done
pause 4

say "3 · Synthesis: the database said who was big; the web says who is live"
CTX=$(for S in "${TOP3[@]}"; do echo "[$S]"; cat "$T/$(echo "$S" | tr ' &' '__').txt"; done)
t0=$SECONDS
ask "Do not use any tools. Keep every line under 110 characters. Below are research notes from three parallel researcher agents on Alzheimer disease programs. Write a compact Markdown table Sponsor | Update | Source (one row per sponsor, Update under 70 characters, Source = one short domain name like fda.gov or roche.com) using only these notes, then a 3-sentence synthesis titled \"What this means for the Alzheimer trial landscape\" that contrasts historical trial counts with today's live pipeline. Notes: $CTX" "synth-$RANDOM" | fold -s -w 120 | reveal
dim "⏱ $((SECONDS - t0))s · $MODEL via OCI Generative AI"
pause 5

say "4 · Deep dive: one approved program, from the regulator's own pages"
t0=$SECONDS
ask 'Execute now, do not narrate, exactly one tool call per message and wait for its result. Never call juice_* tools. Deep research on donanemab (Eli Lilly, Alzheimer disease). Step 1: call web_search_tool with query "donanemab FDA approval Kisunla label". Step 2: call web_fetch with url = the most authoritative result (fda.gov, lilly.com, nejm.org or a major news site) and max_bytes 12000. Step 3: call web_fetch with url = a second source and max_bytes 12000 (skip 403s, take the next result). Step 4: call memory_store with topic alzheimers-programs and a note of the key facts with URLs. Step 5: reply with: Mechanism; Pivotal trial and primary result; Approval status and dosing; Key safety signal with rates; Open questions; Sources (the URLs you fetched); MEMORY_SAVED.' "deep-$RANDOM" | fold -s -w 110 | reveal
dim "⏱ $((SECONDS - t0))s · $MODEL via OCI Generative AI · SearXNG · web_fetch · memory_store"
pause 5

say "5 · Memory: the brief is kept for the next question"
LB="$(tfout lb_public_ip)"; CA="$(mktemp)"; tfout lb_ca_certificate_pem > "$CA"
TOKEN=$(oci secrets secret-bundle get --secret-id "$(tfjson secret_ids | jq -r .core_token)" --profile "$PROFILE" --region "$HOME_REGION" --query 'data."secret-bundle-content".content' --raw-output | base64 -d)
curl -s --max-time 60 --cacert "$CA" -X POST "https://$LB/rpc" -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"openhuman.memory_recall_memories","params":{"namespace":"global","limit":1}}' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); m=(d.get("result",{}).get("data",{}).get("memories") or [{}])[0]; print(m.get("content","")[:700])' | fold -s -w 110 | reveal
dim "read back from the memory tree on the VM · Ollama bge-m3 embeddings"
rm -f "$CA"; unset TOKEN
pause 4
say "DEMO_DONE · github.com/kamelhar/openhuman-oci"
[ -n "${DEMO_TIMING_FILE:-}" ] && echo $((SECONDS - DEMO_T0)) > "$DEMO_TIMING_FILE"
rm -rf "$T"
