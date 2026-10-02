# Prompts for the Alzheimer's trial landscape use case

Imperative, numbered prompts work best on the prompt-guided tool dialect: one
tool call per message, explicit tool names, explicit output shape. Send them
with `deploy/scripts/ask.sh "<prompt>" <thread>`.

## Reliability recipe (prompt-guided tool dialect, gpt-4.1 at temperature 0.2)

Measured on 2026-10-02 against the OCI core:

- **One tool call per message, wait for the result.** Several calls in one
  message leak as text.
- **Bound fetches:** `web_fetch` with `max_bytes 12000`. Larger pages come back
  as a tinyjuice handle and the model then calls `juice_*` tools in the wrong
  syntax; say "never call juice_* tools" and keep pages small instead.
- **Name tools and arguments explicitly**, number the steps, fix the output shape.
- **Show the exact textual form the harness parses** when a run leaks calls as
  text: `<tool_call>{"name":"web_fetch","arguments":{"url":"...","max_bytes":12000}}</tool_call>`
  (tinyagents `XmlDialect`); Python-style `name(a="x")` inside the tags is a
  different grammar and was not recovered in our runs.
- **Fan-out that works today:** run one `inference_agent_chat` per sponsor in
  parallel from the client and synthesise in a fourth turn. The orchestrator's
  `spawn_async_subagent` enum is compiled from the default definition and does
  not pick up `agent_registry_update` of `subagents.allowlist` (upstream issue);
  the team RPCs start a worker but expect it to claim and complete tasks itself.
- **Prefer regulator and official pages** (fda.gov, docs.oracle.com); many news
  and blog sites return 403 to the fetcher, the browser gets through.
- **Expect an occasional fast failure** from the 64-character tool-call id cap
  on OCI (upstream #6933); retry the same prompt once.

With these, the deep-dive brief below succeeded with FDA sources and a memory
write in about 20 seconds.

## 1. Governed SQL through the managed MCP server (needs the user token in Vault)

```
Execute now, do not narrate, one tool call per message.
Step 1: call tool_search with query "oracle-db execute sql".
Step 2: call the oracle-db execute-sql tool with:
  select count(*) total, sum(case when overall_status='RECRUITING' then 1 else 0 end) recruiting
  from clinical_trials where phase like '%PHASE3%'
Step 3: call it again with:
  select lead_sponsor, count(*) trials, sum(enrollment) enrolled
  from clinical_trials where phase like '%PHASE3%' and sponsor_class='INDUSTRY'
  group by lead_sponsor order by trials desc fetch first 5 rows only
Step 4: call it again with:
  select nct_id, title, enrollment, overall_status from clinical_trials
  where phase like '%PHASE3%' and overall_status='RECRUITING' order by enrollment desc nulls last fetch first 5 rows only
Step 5: reply with the three results as Markdown tables and one sentence on what stands out. Nothing else.
```

## 2. Fan-out: one researcher per sponsor

```
Execute now, do not narrate, one tool call per message.
The top Phase 3 industry sponsors from our database are <S1>, <S2>, <S3>.
Step 1: call spawn_async_subagent with agent_id "researcher" and prompt
  "Find <S1>'s most important Alzheimer disease news or pipeline update from 2025-2026
   (approvals, phase 3 readouts, discontinuations). Return 3 bullets with source URLs."
Step 2: same for <S2>. Step 3: same for <S3>.
Step 4: call list_subagents, then continue_subagent on each until all three have returned.
Step 5: reply with a Markdown table Sponsor | Update | Source URL (up to 9 rows) and a
  3-sentence synthesis titled "What this means for the Alzheimer trial landscape".
```

## 3. Deep dive on one program

```
Execute now, do not narrate, exactly one tool call per message and wait for its result. Never call juice_* tools.
Deep research on <PROGRAM> (<SPONSOR>, Alzheimer disease).
Step 1: call web_search_tool with query "<PROGRAM> FDA approval label".
Step 2: call web_search_tool with query "<PROGRAM> phase 3 results ARIA".
Step 3: call web_fetch on the regulator or label page with max_bytes 12000.
Step 4: call web_fetch on the sponsor announcement with max_bytes 12000.
Step 5: call web_fetch on one peer-reviewed or major-news source with max_bytes 12000 (skip 403s, take the next result).
Step 6: call memory_store with topic alzheimers-programs and a note of the key facts with URLs.
Step 7: reply with: Mechanism; Pivotal trial and primary result; Approval status and dosing;
  Key safety signal with rates; Open questions; Sources (the URLs you fetched); MEMORY_SAVED.
```

## 4. Browser fallback when a source blocks the fetcher

```
Execute now, do not narrate, one tool call per message.
Step 1: call tool_search with query "browser navigate snapshot".
Step 2: call browser_navigate with arguments {"url":"<URL that returned 403>"}.
Step 3: call browser_snapshot with arguments {}.
Step 4: reply with the 5 most important facts on that page, each quoted briefly, then the URL.
```

## 5. Memory follow-up

```
Call memory_recall with arguments {"query":"<PROGRAM> Alzheimer","limit":5}. Answer in three
sentences using only what it returned and list the URLs it contains. If it returned nothing,
reply exactly MEMORY_EMPTY.
```
