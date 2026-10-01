# openhuman-oci

Reference architecture for running [OpenHuman](https://github.com/tinyhumansai/openhuman)
on Oracle Cloud Infrastructure, with OCI Generative AI as the model provider and
Oracle AI Database reached through Oracle's managed MCP servers.

## What OpenHuman is

OpenHuman is an open-source (GPL-3.0) personal AI assistant from TinyHumans. It
is three things in one Rust binary:

1. **A memory.** It pulls your email, chat, docs, calendar and code through 118+
   OAuth integrations every twenty minutes, normalises everything to Markdown,
   chunks and scores it, and folds it into per-source / per-topic / per-day
   summary trees stored in SQLite and mirrored as an Obsidian vault you can edit.
2. **An orchestrator.** Agents run on durable graphs (tinyagents / tinyflows):
   they checkpoint, pause for approval, resume, spawn sub-agent fleets three
   levels deep, and leave replayable run journals. A fast reflex agent triages;
   a reasoning core does multi-step work.
3. **A researcher.** Native tools for web search, browser and computer control,
   coding, voice, scheduling, plus any MCP server or skill from the public
   registries. It also reaches you over Slack, Telegram, email and other
   channels, so it works while the desktop app is closed.

The desktop app (Tauri + React) is a shell. All logic lives in `openhuman-core`,
which also ships as a headless container, a CLI, a TUI, an embeddable Rust
library and a read-only MCP server. This repository is about deploying that core
on OCI.

## Repository layout

| Path | Contents |
| --- | --- |
| `docs/ARCHITECTURE.md` | The reference architecture: deployment shapes, OCI service mapping, security posture, known gaps, phased plan |
| `docs/UPSTREAM.md` | Where OCI-related work should land upstream in the TinyHumans repos, and their contribution rules |
| `deploy/terraform/` | Terraform for the Always Free pilot: compartment, network, Vault, ADB, Database Tools MCP Server, Ampere VM, load balancer, bastion |
| `deploy/vm/` | Assets the VM fetches at boot: core Dockerfile around the upstream arm64 tarball, compose file, secret/config renderer, systemd timer |
| `deploy/scripts/` | Operator steps Terraform cannot do: GenAI API key, CA trust, MCP registration, demo data |
| `docs/PILOT-ACCOUNT-VALIDATION.md` | Read-only inventory proving the pilot fits a personal pay-as-you-go account on Always Free resources |

## Status

Phase 1 deployed to a personal tenancy on 2026-10-01: headless core on an Always Free Ampere VM answering through OCI Generative AI with no TinyHumans account, Always Free Autonomous Database 26ai seeded with a demo table, managed Database Tools MCP Server created and awaiting a user token. Findings are in `docs/ARCHITECTURE.md`; the run book is `deploy/README.md`.

## Privacy

Nothing in this repo may contain tenancy or compartment OCIDs, local OCI profile
names, account holder names, or credentials. Use placeholders and read secrets
from the environment or OCI Vault.
