# The pilot

What was deployed from [`ARCHITECTURE.md`](ARCHITECTURE.md), why it differs from the
reference design, and what the first apply taught us. Account validation that
preceded it is in [`PILOT-ACCOUNT-VALIDATION.md`](PILOT-ACCOUNT-VALIDATION.md).

## Decisions (2026-10-01)

The first deployment in `deploy/` narrows Shape A to what fits Always Free:

| Topic | Reference design | Pilot |
| --- | --- | --- |
| Compute | OKE or Container Instances, one core per user | One Ampere A1 VM (3 OCPU / 18 GB) running Docker Compose. Same container, same workspace layout, so moving to OKE later is a manifest change |
| Core image | Upstream amd64 image | Upstream ships a prebuilt `aarch64` core tarball with each release. The VM wraps it in the upstream runtime image at boot. No Rust build, no registry |
| Chat inference | LiteLLM gateway with resource-principal signing | OpenHuman calls the OCI GenAI OpenAI-compatible endpoint directly with a GenAI API key from Vault. LiteLLM is deferred: its proxy cannot use instance principals from config, so it would need a user API key too |
| Embeddings | Via the gateway (Cohere embed on OCI) | Ollama `bge-m3` on the VM. Free, local, upstream's recommended embedder |
| Client path | Load balancer with path allowlist | Same. Public flexible LB restricted to the operator's CIDR, generated CA, allowlist `/rpc`, `/health`, `/events` |
| Database access | Database Tools MCP Server | Same. Resource-principal server and connection, ADB over TLS with a VCN access list through a Database Tools private endpoint |

## Results (2026-10-01, first apply)

The stack in `deploy/` was applied to a personal pay-as-you-go tenancy. What
worked, what had to change, and what was learned:

| Area | Result |
| --- | --- |
| Terraform apply | 51 resources on first apply, one failure (LB rule set), fixed in a second apply. Everything Always Free except GenAI tokens |
| Core image | Upstream's prebuilt `aarch64` tarball is linked against glibc 2.39. Debian bookworm (2.36) fails at exec; the runtime image is Ubuntu 24.04 |
| Keyring | The headless core defaults to the `encrypted_file` keyring whose master key must come from an OS keychain. Containers have none and upstream offers no injection path, so the pilot uses `OPENHUMAN_KEYRING_BACKEND=file` on the encrypted block volume |
| Inference without a TinyHumans account | Custom cloud providers (`inference_url` + `api_key`) are gated behind an active TinyHumans session or API key. Caller-owned runtimes are not. OCI GenAI's OpenAI-compatible endpoint is therefore wired as the `local-openai` runtime (`LOCAL_OPENAI_URL`, bearer in local-AI settings) with every role pinned to it. A chat turn through the headless core returned from OCI GenAI in 1.7 s with no account |
| Load balancer | OCI LB cannot use PATH conditions in ALLOW rules. The allowlist is a path route set: listed paths go to the core, the default backend set is empty. Verified: `/health` 200, `/rpc` without token 401, other paths 502 |
| Bastion | Sessions were closed by the bastion because this laptop's SSH egress IP differs from its HTTPS egress IP (split tunnel). `bastion_client_cidrs` is a separate variable for that case |
| Database access list | Same split-egress effect: the laptop's database traffic was rejected by the ADB ACL. Seeding ran from the VM through the service gateway instead, using the instance principal to read the ADMIN password from Vault |
| MCP server auth | A client-credentials OAuth client (created in Terraform) gets a valid token for the MCP audience, but IAM evaluates it as principal type `user` with the domain-app OCID and no policy form authorizes it (`request.principal.id`, `request.user.id`, even an unconditional any-user grant). The MCP invoke service log names the missing permission. Supported shapes are user tokens: personal access token, OAuth sign-in, or a trusted client acting on behalf of a user. The pilot stores a personal access token in Vault and the VM registers the server from there |
| Embeddings | Ollama `bge-m3` on the VM, 1024 dimensions, reachable from the core container |

## Research stack (2026-10-02)

Two containers were added next to the core so the agent can research without a
TinyHumans account:

| Capability | How | Verified |
| --- | --- | --- |
| Web search | SearXNG container (`searxng/searxng`, JSON output enabled), wired with `OPENHUMAN_SEARXNG_ENABLED` / `OPENHUMAN_SEARXNG_BASE_URL`. The core's search role resolves to `searxng` with no fallbacks | `openhuman.tools_web_search` returned Oracle docs as citations; agent turns show `tool_calls` for search |
| Page reading | Built-in `web_fetch` (HTML to Markdown through tinyjuice), no key | Used in research turns |
| Web navigation | Playwright MCP container (`mcr.microsoft.com/playwright/mcp`, headless Chromium, `--isolated`, streamable HTTP on the compose network). Registered in the core as the `browser` MCP server by the renderer; 25 `browser_*` tools | Agent navigated to oracle.com/mcp, snapshotted the page and listed the seven Oracle MCP servers correctly |
| Memory | `memory_store` / `memory_recall` tools over the memory tree with Ollama embeddings | `MEMORY_SAVED` in the showcase turn; facts land in the `global` namespace |

Showcase turn (`openhuman.inference_agent_chat`, model `openai.gpt-4.1` through
OCI GenAI): browser navigate and snapshot, web search, `web_fetch` of an Oracle
doc, `memory_store`, then a 200-word brief citing only the two pages it opened.
27 seconds, 8 model calls, 8 tool calls.

Two things to know. MCP tools are *deferred*: the model has to call
`tool_search` before a `browser_*` tool is in view, which it does when the task
says "open ... in the browser"; a config-side `direct_tools` list exists for
servers declared in `config.toml` but not for the registry path the renderer
uses. And the `local-openai` runtime is `PromptGuided` for tool calling (textual
dialect, not native function calling); it worked reliably with gpt-4.1 in every
run, but an unloaded tool name can leak into the reply as text.

### Memory recall gap (2026-10-02)

`memory_store` from an agent turn lands in the memory tree (the
`openhuman.memory_recall_memories` RPC lists the note with its URLs), but the
agent-side `memory_recall` tool returns nothing for the same facts, with or
without a topic. The likely cause is that semantic recall needs embeddings the
background indexer has not produced yet; the periodic memory sync runs every
20 minutes and some services stay deferred without a TinyHumans session. The
showcase script therefore tries the agent's recall first and falls back to
reading the stored note through the RPC. Open question for upstream.

## Showcase video (2026-10-02)

`media/openhuman-oci-showcase.mp4` (71 s, 1600x1000): title card, the scripted
terminal session against the live deployment (edge checks, browser navigation,
research with memory write, memory read-back, MCP server status), the page the
headless browser saw, and an outro. Produced by `deploy/scripts/demo.sh` under
`vhs media/demo.tape`, then `media/assemble.sh`. The agent model for the
recording is gpt-4.1 at temperature 0.2; the gpt-5 family is unusable on the
`local-openai` route today because the runtime sends `max_tokens`.

## Current state

| Item | State |
| --- | --- |
| Terraform | Clean plan after the fix-up applies. Everything in one compartment, `terraform destroy` removes it all |
| Core | Healthy, answering through OCI GenAI (`local-openai` mode), Ollama embeddings, SearXNG search, Playwright browser |
| Database | Autonomous AI Database 26ai Always Free, `ORDERS` demo table seeded from the VM |
| MCP | Database Tools MCP Server created, MCP_Operator granted to the users group, waiting for a personal access token in Vault (`deploy/scripts/03-register-mcp.sh`) |
| Client | Desktop app connects with the LB URL and the core token after trusting the generated CA (`deploy/scripts/02-trust-lb-cert.sh`) |

## Operating notes

- Secrets and settings reach the core through `openhuman-render.timer` on the VM every two minutes. Changing a Vault secret is enough; the renderer restarts the core only when `core.env` changes.
- Admin access: create a bastion port-forward session to the VM's private IP on 22, then `ssh -4 -N -L 2222:<vm-ip>:22 <session-ocid>@host.bastion.<region>.oci.oraclecloud.com` and `ssh -p 2222 ubuntu@127.0.0.1`. If the bastion closes the connection right after authentication, your SSH egress IP is not in `bastion_client_cidrs`.
- Bootstrap log on the VM: `/var/log/openhuman-bootstrap.log`. Core logs: `docker logs openhuman-core`.
- `openhuman.inference_agent_chat_simple` is the quickest end-to-end check from outside: it exercises the LB, the token, the BYOK route and OCI GenAI in one call.
