# Pilot account validation (2026-10-01)

Read-only inventory of the personal pay-as-you-go OCI account (upgraded from
Free Tier) against the Shape A pilot in `ARCHITECTURE.md`. No resources were
created. Identifiers are deliberately omitted.

## Verdict

The pilot fits. Everything except model inference lands on Always Free
resources. The only recurring cost is OCI Generative AI tokens.

## Component by component

| Component | Needed | Account state | Free? |
| --- | --- | --- | --- |
| Regions | GenAI region + one general region | Home region Toronto, plus Chicago (GenAI) and Phoenix subscribed | n/a |
| Identity domain | Required by Database Tools MCP Server (`--domain-id`) | Default domain active | yes |
| OKE | 1 cluster | 1 basic cluster allowed, 1000 nodes, Kubernetes 1.34 to 1.36 available | control plane free on basic clusters |
| Compute (core + gateway) | 2 vCPU / 2 GB class | Ampere A1: Always Free allowance is 4 OCPU / 24 GB; 1 OCPU / 6 GB already used by an existing instance, so 3 OCPU / 18 GB remain. AMD E4/E5/E6 Flex available at cost. E2.1.Micro too small | yes on A1 |
| Container Instances | alternative to OKE | Service reachable in Toronto, none deployed | no, hourly |
| Load balancer | 1, with path allowlist | 1 Always Free 10 Mbps micro flexible LB available | yes |
| WAF | optional rate limit on /rpc | Service available | free allowance, then per request |
| NAT gateway | 1 | Limit is 1 per region, none created yet. Existing VCN has only an internet gateway | yes |
| Block Volume | ~20 GB per core workspace | 50 GB of the 200 GB Always Free allowance used (existing boot volume), 150 GB free | yes |
| Vault | tokens, master key, DB credential for Database Tools | 10 virtual vaults allowed, none exist | virtual vault with software keys is free; verify secret count allowance |
| Autonomous AI Database | 1 for the demo | 2 Always Free ADBs allowed, 0 used; 26ai available as Always Free in Toronto (23ai is the default) | yes |
| Database Tools connection + MCP Server | 1 each | Service reachable in Toronto, none exist. Toolset `BUILT_IN_SQL_TOOLS` exposes `dbtools_execute_sql` with roles `MCP_Operator` and `MCP_Administrator`. Needs a Database Tools connection, the identity domain, and a Vault secret for the DB credential | MCP Server is zero cost per Oracle |
| OCI Generative AI | chat, embeddings, rerank | 135 models visible in Chicago: GPT line, Grok, Llama 3/4, Gemini 2.5, Cohere Command, 11 Cohere embed models, 3 rerank models. Two GenAI API keys already active | no, per token |

## Gotchas found

1. **arm64.** Upstream `openhuman-core` images are amd64 only. On Always Free
   Ampere A1 you build from source with the pinned Rust 1.96.1 toolchain. The
   LiteLLM gateway has arm64 images. Alternative: a small paid AMD E5.Flex VM.
2. **Cross-region.** GenAI lives in Chicago, everything else in Toronto. The
   gateway reaches the Chicago inference endpoint over the NAT gateway. A
   service gateway does not help because it is regional.
3. **CLI auth.** The local shell exports `OCI_CLI_AUTH=security_token`, which
   breaks API-key profiles. Prefix commands with `OCI_CLI_AUTH=api_key`.
4. **Ampere capacity.** Toronto has one availability domain. A1 "out of host
   capacity" errors are common on Always Free; retry or schedule.
5. **Database Tools MCP Server OAuth.** Create the Database Tools connection and
   Vault secret first; the MCP Server create call requires both plus the
   identity domain. Register OpenHuman as an MCP client in the domain, or use a
   personal access token as a static bearer header.

## Cost estimate for a two-week pilot

| Item | Estimate |
| --- | --- |
| Always Free resources above | 0 |
| GenAI tokens (one user, memory embeddings + chat) | low single-digit dollars per day at most; dominated by the reasoning tier |
| Optional amd64 VM instead of A1 build | a few dollars per week |
