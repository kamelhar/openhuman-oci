# Contributing OCI support upstream

OpenHuman is GPL-3.0 and actively accepts external PRs. The main repo is
`tinyhumansai/openhuman` (40k stars, ~4k forks, ~250 open issues, dozens of
merges per day as of 2026-10-01). Most functionality lives in vendored Rust
crates under `vendor/`, each a separate repo in the `tinyhumansai` org pinned by
release tag. A change to a provider or memory engine lands in its crate repo
first, is released, then re-pinned in the main repo.

As of 2026-10-01 there are no OCI or Oracle mentions in upstream issues, PRs or
code. The field is open. Issues already tracking the headless gaps this repo
ran into: [#6601](https://github.com/tinyhumansai/openhuman/issues/6601)
(key-first onboarding, run with your own providers and no sign-in wall),
[#4844](https://github.com/tinyhumansai/openhuman/issues/4844) (headless Linux
build with CI), [#5444](https://github.com/tinyhumansai/openhuman/issues/5444)
(desktop client to remote headless core), [#5199](https://github.com/tinyhumansai/openhuman/issues/5199)
(slim and headless dependency profiles). Comment there before opening new ones.

## Status (2026-10-02)

| Item | Upstream | State |
| --- | --- | --- |
| Compose: writable projects volume under `read_only` | issue [#6925](https://github.com/tinyhumansai/openhuman/issues/6925), PR [#6928](https://github.com/tinyhumansai/openhuman/pull/6928) | open |
| Docs: glibc floor, headless without account, container keyring, OCI recipe | issue [#6927](https://github.com/tinyhumansai/openhuman/issues/6927), PR [#6929](https://github.com/tinyhumansai/openhuman/pull/6929) | open |
| Keyring master key injection for headless (`OPENHUMAN_KEYRING_MASTER_KEY`) | issue [#6926](https://github.com/tinyhumansai/openhuman/issues/6926), PR [#6935](https://github.com/tinyhumansai/openhuman/pull/6935) | PR open: `OPENHUMAN_KEYRING_MASTER_KEY` / `_FILE` in the encrypted_file backend, 15 tests |
| Tool-call ids exceed the 64-char limit OpenAI-compatible endpoints enforce (69 chars) | issue [#6933](https://github.com/tinyhumansai/openhuman/issues/6933) | open; fix belongs in tinyagents `CallId` |
| Orchestrator `subagents.allowlist` update not reflected in the spawn enum | issue [#6934](https://github.com/tinyhumansai/openhuman/issues/6934) | open |
| BYOK without a TinyHumans session | comment on [#6601](https://github.com/tinyhumansai/openhuman/issues/6601#issuecomment-5952668753) with evidence and a minimal proposal | awaiting maintainer |
| OCI GenAI provider preset, native embeddings | not filed | after the above land |
| `local-openai` runtime: opt-in native tool calling for hosted OpenAI-compatible endpoints (profile is `PromptGuided`); `direct_tools` for registry-declared MCP servers | not filed | evidence from the research showcase in `docs/PILOT.md` |
| OpenAI-compatible transport sends `max_tokens` to prefixed reasoning model ids (`openai.gpt-5.4` on OCI) and gets HTTP 400 `Use max_completion_tokens`; `is_reasoning_model` should match after a vendor prefix or be configurable | not filed (tinyinference) | reproduced 2026-10-02 on OCI GenAI |
| `model_override` on `inference_agent_chat` is ignored when roles are pinned to a local runtime | not filed | turn log keeps the pinned model |
| Agent `memory_recall` tool returns empty while `memory_recall_memories` RPC lists the stored note (headless, no session) | not filed | likely embeddings/indexing gated or lagging; see `docs/PILOT.md` |

Fork: `fede-kamel/openhuman`. Branches: `fix/compose-projects-volume`, `docs/headless-deploy-gaps`.

## Where each piece lands

| Contribution | Repo | Where | Precedent |
| --- | --- | --- | --- |
| OCI deploy recipe (Resource Manager stack or Container Instances, docs page) | `tinyhumansai/openhuman` | `.oci/` next to `.do/app.yaml` and `.fly/fly.toml`; new section in `gitbooks/features/cloud-deploy.md` | DigitalOcean and Fly recipes already exist |
| `oci` BYOK provider preset (OCI GenAI OpenAI-compatible endpoint, bearer API key) | `tinyhumansai/tinyinference` first (`tinyinference-llm` providers), then `openhuman` slug resolution in `crates/openhuman-core/src/inference/provider/factory/cloud_slug.rs` and the app LLM settings preset list | 26 existing slugs (openrouter, groq, fireworks, cerebras, ...) |
| OCI GenAI embeddings (native API, since not on the OpenAI-compatible path) | `tinyhumansai/tinyinference` (`tinyinference-embeddings`) | Cohere and Voyage adapters |
| Oracle AI Database memory driver (26ai vector + Oracle Text hybrid recall) | `tinyhumansai/tinymemory` | new crate alongside `tinymemory-remote`; must pass `tinymemory-conformance` | Supermemory, Mem0, Cognee dialects |
| Remote MCP OAuth 2.0 authorization-code flow headlessly (needed for Database Tools MCP Server) | `tinyhumansai/tinymcp` | check first whether the OAuth-callback helper already covers it | |
| OCI OpenSearch as a search engine | `tinyhumansai/tinysearch` | optional, low priority | SearXNG self-hosted toggle |
| Oracle MCP servers in the registry | upstream registries (Smithery, official MCP registry), not OpenHuman | | |

## Can code from this repository go upstream?

Short answer: the Terraform and OCI wiring cannot, two small pieces can almost
as-is, and the most valuable contributions are Rust changes this repo only
*worked around*. Licensing is not an obstacle: this repository is Apache-2.0,
upstream is GPL-3.0, and Apache-2.0 code may be contributed into a GPL-3.0
project (the contributor relicenses their own work on submission; upstream has
no CLA or DCO).

| What is here | Upstreamable? | Form | Notes |
| --- | --- | --- | --- |
| `deploy/vm/Dockerfile.core` (runtime image on Ubuntu 24.04 around the release tarball) | Yes, adapted | PR: `Dockerfile.release` or an arm64 image publish job | Upstream's Dockerfile builds from source on Debian bookworm, whose glibc cannot run the published aarch64 tarball. A release-based image is faster to build and multi-arch |
| `deploy/vm/compose.yaml` projects volume | Yes | One-line PR to `docker-compose.yml` | `read_only: true` breaks `~/OpenHuman/projects` creation; a tmpfs or volume fixes it |
| `deploy/vm/render_config.py` (push BYOK settings via RPC after boot) | No, but it defines the gap | Rust PR: boot-time env for BYOK (`OPENHUMAN_INFERENCE_URL`, `OPENHUMAN_INFERENCE_API_KEY`, `OPENHUMAN_DEFAULT_MODEL`, `OPENHUMAN_EMBEDDINGS_PROVIDER`) next to `OPENHUMAN_BACKEND_API_KEY` in `security/credentials/ops/boot_env.rs`, calling the same completion path as `config_update_model_settings` | Removes the need for any post-boot RPC choreography in headless deploys |
| `OPENHUMAN_KEYRING_BACKEND=file` workaround | No, but it defines the gap | Rust PR: `OPENHUMAN_KEYRING_MASTER_KEY` (hex) or `_FILE` for the `encrypted_file` backend in `security/keyring/encrypted_file_backend.rs` | Lets containers keep encrypted secrets without an OS keychain |
| `local-openai` mode for OCI GenAI | No code, a documentation fact (and evidence for #6601) | Docs PR to `gitbooks/features/model-routing/local-and-byok-models.md` and `cloud-deploy.md`: headless BYOK works through caller-owned runtimes; custom cloud providers need a session | Or a maintainer decision to exempt custom cloud providers in `serve` mode when no backend credential exists |
| OCI GenAI as a provider preset | Yes | PR to `tinyinference` (provider adapter, OpenAI-compatible, regional endpoint template) then the preset slug in `openhuman` | Needs a region parameter; presets today have fixed endpoints |
| OCI GenAI native embeddings | Yes | PR to `tinyinference-embeddings` | Embeddings are not on OCI's OpenAI-compatible path |
| `deploy/terraform/*` | No | Link from `cloud-deploy.md` as a community recipe, like the DigitalOcean and Fly entries | Too large and OCI-specific for upstream; a one-file Resource Manager stack could be offered later |
| `deploy/scripts/*` | No | None | Operator glue around the OCI CLI |
| Database Tools MCP Server wiring and the auth finding | No | Maybe a gitbook note under MCP servers: remote servers with bearer headers, token refresh | The IAM finding belongs to Oracle, not OpenHuman |

Upstream's gates apply to all of the above: 80 percent diff coverage on changed
lines, a failure-path test, no live network in tests, and vendored crates are
pinned by release, so `tinyinference` changes land there first.

## Findings from the pilot worth upstreaming

| Finding | Suggested change | Repo |
| --- | --- | --- |
| Headless core cannot store secrets: `encrypted_file` keyring needs an OS keychain master key and there is no way to inject one | `OPENHUMAN_KEYRING_MASTER_KEY` (or a file path) for the `encrypted_file` backend; document `OPENHUMAN_KEYRING_BACKEND=file` as the current headless fallback | openhuman |
| BYOK cloud providers are gated behind a TinyHumans session even in `serve` mode, while local runtimes are not | Either exempt custom cloud providers when `OPENHUMAN_BACKEND_API_KEY` is absent by design, or document the `local-openai` runtime as the supported headless BYOK path | openhuman |
| Release tarballs for `aarch64-unknown-linux-gnu` require glibc 2.39 but the repo Dockerfile's runtime stage is Debian bookworm (2.36) | Publish an arm64 image, or note the glibc floor next to the tarball | openhuman |
| `read_only: true` in the upstream compose breaks the core's `~/OpenHuman/projects` creation | Add a tmpfs or volume for `/home/openhuman/OpenHuman` in `docker-compose.yml` | openhuman |
| `openhuman.inference_agent_chat_simple` is the simplest smoke test for a remote core | Mention it in the cloud-deploy page | openhuman docs |

## Contribution rules that will bite

From `CONTRIBUTING.md` and `.github/PULL_REQUEST_TEMPLATE.md`:

- Toolchain pins: Rust 1.96.1 with rustfmt and clippy, Node 24+, pnpm 10.10.0,
  ripgrep for the pre-push hook. Run `git submodule update --init --recursive vendor/`.
- Tests required: happy path plus at least one failure path.
- **Diff coverage of at least 80 percent** on changed lines, enforced in CI
  (`pnpm test:coverage` and `pnpm test:rust`).
- Update `docs/TEST-COVERAGE-MATRIX.md` for any added or renamed feature, and
  list the feature IDs under `## Related` in the PR.
- No new external network dependencies in tests; use the mock backend.
- Link an issue with `Closes #NNN`. Open the issue first.
- Beginners guide: `docs/CONTRIBUTING-BEGINNERS.md`. Architecture:
  `gitbooks/developing/`. Agent rules: `AGENTS.md`.
- No CLA or DCO found in `.github`. Code of Conduct applies.
- Security issues go through `SECURITY.md`, not public issues.
- Issue labels worth filtering on: `good first issue`, `help wanted`,
  `rust-core`, `mcp-rpc`, `memory`, `local-ai`, `infra-ci-release`, `docs`.

## Suggested order

1. Open a discussion or issue: "OCI deployment recipe and OCI Generative AI
   provider preset". Low risk, establishes the thread.
2. PR 1: `.oci/` deploy recipe plus docs. Pure config and Markdown, minimal
   coverage burden.
3. PR 2: `oci` slug in tinyinference, then re-pin in openhuman. Needs mocked
   transport tests.
4. PR 3: OCI GenAI native embeddings adapter.
5. Later: Oracle AI Database tinymemory driver, once phase 1 of
   `ARCHITECTURE.md` has proven the deployment.

Keep tenancy and compartment OCIDs, profile names and account references out
of every upstream PR, issue and commit.
