# Use case: the Alzheimer's trial landscape, from governed data to the live web

A research analyst wants a defensible brief on where Alzheimer's disease drug
development stands: which sponsors are active, which Phase 3 programs are live,
what just read out or got approved, and what that means for the field. Today
that is a day of spreadsheet work over ClinicalTrials.gov exports plus hours of
browsing. Here the agent does it in one conversation, and the data never leaves
the tenancy.

## Data

`CLINICAL_TRIALS` in the Autonomous AI Database 26ai: 4,300 registered
Alzheimer's disease studies from the public ClinicalTrials.gov v2 API
(registry metadata only: identifiers, titles, phase, status, sponsor,
enrollment, dates, conditions, interventions, site counts; no patient data).
Loaded from the VM through the service gateway; refreshable with the same
script. Snapshot numbers at load (2026-10-02):

| Slice | Count |
| --- | --- |
| Studies | 4,300 (start dates 1981 to 2028) |
| Phase 3 | 319 |
| Phase 2 | 602 |
| Recruiting | 626 |
| Completed | 2,284 |
| Top industry sponsors | Pfizer 62, Eli Lilly 59, Avid Radiopharmaceuticals 42, Merck 31, GSK 31 |

## The conversation

1. **Governed SQL through MCP.** "How many Phase 3 Alzheimer trials are
   recruiting, who sponsors them, and which have the largest enrollment?" The
   agent calls the Database Tools MCP Server's `dbtools_execute_sql` under the
   user's identity-domain role. No wallet, no connection string in the agent.
2. **Fan-out research.** For the top three sponsors the orchestrator spawns the
   `researcher` sub-agent in parallel; each searches the web through the
   in-tenancy SearXNG, reads two or three authoritative pages, and returns
   sourced facts.
3. **Deep dive.** For the lead program it produces a structured brief:
   mechanism, pivotal trial and result, approval status, safety signal, open
   questions, sources.
4. **Browser when needed.** If a source blocks the fetcher, the agent opens it
   in the headless browser and reads the snapshot.
5. **Memory.** Facts land in the memory tree under a topic so the next question
   starts from what it already learned.
6. **Output.** A brief with a table from the database, a table from the web,
   and a Sources list, all traceable.

## Why this is the right showcase

- Real, public, clinical-domain data without any patient information.
- Every hop is governed: IAM for the database, Vault for secrets, the VCN for
  the database access list, a path-allowlisted edge for the client.
- It exercises every capability of the stack at once: SQL via MCP, search,
  page reading, browser, sub-agents, memory, and OCI Generative AI, with no
  vendor account.
- The same conversation works for any Oracle Database a customer already has;
  only the table changes.

## Status

Steps 2 to 6 run today. Step 1 waits for the operator's personal access token
for the MCP server (`deploy/scripts/03-register-mcp.sh`).
