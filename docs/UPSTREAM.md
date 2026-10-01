# Contributing OCI support upstream

OpenHuman is GPL-3.0 and actively accepts external PRs. The main repo is
`tinyhumansai/openhuman` (40k stars, ~4k forks, ~250 open issues, dozens of
merges per day as of 2026-10-01). Most functionality lives in vendored Rust
crates under `vendor/`, each a separate repo in the `tinyhumansai` org pinned by
release tag. A change to a provider or memory engine lands in its crate repo
first, is released, then re-pinned in the main repo.

As of 2026-10-01 there are no OCI or Oracle mentions in upstream issues, PRs or
code. The field is open.

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
