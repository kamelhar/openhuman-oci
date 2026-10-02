# Prompts for the Alzheimer's trial landscape use case

Imperative, numbered prompts work best on the prompt-guided tool dialect: one
tool call per message, explicit tool names, explicit output shape. Send them
with `deploy/scripts/ask.sh "<prompt>" <thread>`.

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
Execute now, do not narrate, one tool call per message.
Deep research on <PROGRAM> (<SPONSOR>, Alzheimer disease).
Step 1: call web_search_tool with query "<PROGRAM> FDA approval label".
Step 2: call web_search_tool with query "<PROGRAM> phase 3 results ARIA".
Step 3: call web_fetch on the regulator or label page.
Step 4: call web_fetch on the sponsor announcement.
Step 5: call web_fetch on one peer-reviewed or major-news source (skip 403s, take the next result).
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
