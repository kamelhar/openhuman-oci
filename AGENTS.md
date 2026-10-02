# AGENTS.md: the codex for building and operating this stack

This file is for coding agents (OpenAI Codex, Claude Code, OpenHuman's own
coder, a human in a hurry). It states what this repository is for, the order
of operations, the invariants, and what must never happen. Humans start with
`README.md`; agents start here. `CLAUDE.md` is a symlink to this file.

## Purpose, in priority order

1. **Demo.** Show OpenHuman running on OCI with OCI Generative AI and Oracle
   AI Database through the managed MCP server, on Always Free resources, with
   no third-party account. Everything must stay reproducible from `terraform apply`.
2. **Template.** The OCI side is harness-neutral. Keep Terraform free of
   OpenHuman assumptions except in `deploy/vm/`, so another OpenAI-compatible
   agent harness can replace the VM payload.
3. **Upstream.** Turn findings into OpenHuman issues and PRs (`docs/UPSTREAM.md`).
   Workarounds in `deploy/vm/` are temporary; each must point at the upstream
   issue that would retire it.
4. **Personal use.** One operator, one core, their own data. Multi-user is out
   of scope until the OKE phase.

## The user story this serves

An engineer whose company runs on Oracle Database wants a personal AI agent
that works over their own notes, mail and code **and** answers questions from
the company's Oracle data in plain language, keeps working when the laptop is
closed, and does all of it inside the company's OCI tenancy with database
access governed by IAM roles, so that nothing is pasted into a public chatbot
and no database wallet lives on a laptop. Done means: inference in OCI,
database access only through the managed MCP server under the user's identity,
answers remembered, always on, one `terraform apply`, Always Free footprint.

## Map

| Path | Role | Touch when |
| --- | --- | --- |
| `deploy/terraform/` | The stack. One root module. `variables.tf` is the contract | Infra change |
| `deploy/terraform/templates/cloud-init.yaml.tftpl` | Writes `/opt/openhuman/bootstrap.env` on the VM and runs `bootstrap.sh` | New VM-side setting |
| `deploy/vm/bootstrap.sh` | Idempotent first boot: volume, Docker, assets, image, compose, timer | VM runtime change |
| `deploy/vm/Dockerfile.core` | Runtime image around the upstream release tarball (Ubuntu 24.04, glibc 2.39) | New upstream release shape |
| `deploy/vm/compose.yaml` | Core, Ollama (embeddings), SearXNG (search), Playwright MCP (browser). Only the core publishes a port | Container change |
| `deploy/vm/searxng-settings.yml` | SearXNG template; the secret key is generated on the VM at first boot | Search settings |
| `deploy/vm/render_config.py` | Every 2 min: Vault secrets to `core.env`, settings and MCP registration via RPC | Settings or secret flow change |
| `deploy/scripts/` | Operator steps Terraform cannot do | Manual step change |
| `docs/ARCHITECTURE.md` | Design and alternatives | Design change |
| `docs/PILOT.md` | What is deployed and what was learned | After any apply |
| `docs/UPSTREAM.md` | What goes upstream, where, status | After any upstream action |

The VM downloads `deploy/vm/*` from this repository's `main` at boot
(`vm_assets_base_url`, `vm_assets_ref`). **Push before apply.**

## Order of operations

1. `deploy/scripts/00-preflight.sh` (tools, profile, regions).
2. `terraform -chdir=deploy/terraform init && plan && apply`. Expect roughly
   55 resources and 20 minutes. One apply may need a second pass for IAM
   propagation; a clean `plan` afterwards is the acceptance test.
3. `01-genai-api-key.sh` (GenAI key into Vault; the IAM policy for
   `generativeaiapikey` principals already exists from Terraform).
4. `02-trust-lb-cert.sh` on the client machine.
5. Personal access token for the MCP server app from the identity-domain
   console, then `03-register-mcp.sh tokens.tok` (into Vault).
6. `04-seed-demo-data.py` from an allowlisted IP, or run the same SQL on the VM.
7. Verify: `curl --cacert ca.pem https://<lb>/health` is 200; an RPC without
   token is 401; `openhuman.inference_agent_chat_simple` answers; the render
   journal on the VM shows "MCP server registered".

## Invariants

- Every secret lives in OCI Vault and reaches the core only through the VM's
  instance principal. Nothing secret in cloud-init, images, state outputs or git.
- The core VM has no public IP. Clients reach it only through the load
  balancer, which forwards only `/rpc`, `/health`, `/events`.
- The database is reached by agents only through the Database Tools MCP Server
  and its private endpoint. No wallet, no direct SQL from the core.
- Inference runs in `local-openai` mode by default (no TinyHumans session).
  `byok-cloud` mode exists but requires `tinyhumans_api_key`.
- `terraform plan` must be clean after any change. Drift that comes from the
  provider (ADB cores, group schemas, reserved IP attachment) is silenced with
  `ignore_changes`, documented inline.
- Everything is destroyable with `terraform destroy`; the compartment has
  `enable_delete`.
- SearXNG and Playwright MCP are reachable only on the compose network. Never
  publish their ports; the browser can be driven to arbitrary sites.

## Never

- Commit OCIDs, public IPs, OCI profile names, account names, tokens or
  `terraform.tfvars`. Scan before every commit:
  `git grep -n -E "ocid1\.[a-z]+\.oc1\.[a-z0-9-]*\.[a-z0-9]{20,}|API_FREE|BOAT"`.
- Apply against a tenancy you were not told is yours to use.
- Widen `allowed_client_cidrs` to `0.0.0.0/0`. The events stream is
  unauthenticated upstream; the CIDR list is the control.
- Mention Anthropic or Claude in commits or PRs. The author is the operator.

## Validation loop

```bash
terraform -chdir=deploy/terraform fmt -recursive && terraform -chdir=deploy/terraform validate
bash -n deploy/scripts/*.sh deploy/vm/bootstrap.sh
python3 -m py_compile deploy/vm/render_config.py deploy/scripts/04-seed-demo-data.py
```

## Operating the deployed VM

Bastion port-forward session to the VM's private IP on 22, then
`ssh -4 -N -L 2222:<vm-ip>:22 <session-ocid>@host.bastion.<region>.oci.oraclecloud.com`
and `ssh -p 2222 ubuntu@127.0.0.1`. Logs: `/var/log/openhuman-bootstrap.log`,
`docker logs openhuman-core`, `journalctl -u openhuman-render.service`. If the
bastion closes the connection right after authenticating, the SSH egress IP is
not in `bastion_client_cidrs`.

## Upstream work

Follow `docs/UPSTREAM.md`. Upstream rules: sentence-case issue titles, their
issue and PR templates, an issue per PR (`Closes #n`), 80 percent diff coverage
on code changes, no live network in tests, vendored `tiny*` crates change in
their own repos first.
