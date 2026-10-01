# Contributing

Thanks for looking at this. The repository is small and opinionated: it exists
to run [OpenHuman](https://github.com/tinyhumansai/openhuman) on Oracle Cloud
Infrastructure with OCI Generative AI and Oracle AI Database, and to feed what
we learn back upstream. Contributions that serve that goal are welcome.

## What belongs here, and what belongs upstream

| Change | Where |
| --- | --- |
| Terraform, VM bootstrap, operator scripts, OCI-specific docs | here |
| Anything that changes how `openhuman-core` behaves (keyring, BYOK gating, provider presets, compose defaults) | [tinyhumansai/openhuman](https://github.com/tinyhumansai/openhuman) or its `tiny*` crates. See `docs/UPSTREAM.md` for the map |
| Oracle MCP server behaviour | Oracle, via support or the relevant product forum |

If you are unsure, open an issue first.

## Development loop

```bash
terraform -chdir=deploy/terraform fmt -recursive
terraform -chdir=deploy/terraform validate
shellcheck deploy/scripts/*.sh deploy/vm/bootstrap.sh     # if installed
python3 -m py_compile deploy/vm/render_config.py deploy/scripts/04-seed-demo-data.py
```

To test for real you need your own OCI tenancy. Copy
`deploy/terraform/terraform.tfvars.example` to `terraform.tfvars` (gitignored),
run `terraform plan`, and apply only in an account you control. The pilot fits
Always Free resources except Generative AI tokens; see `docs/PILOT.md`.

## Pull requests

- One topic per PR, with a short description of what changed and why.
- Run the development loop above. CI is not set up yet, so reviewers rely on it.
- Keep `terraform plan` clean after your change (no perpetual drift).
- Update the docs that describe what you changed: `deploy/README.md` for the run
  book, `docs/ARCHITECTURE.md` for design, `docs/PILOT.md` for results.

## Never commit

Tenancy, compartment, user or resource OCIDs; public IPs; local OCI profile
names; account holder names; tokens, keys or passwords; `terraform.tfvars`;
Terraform state. Use placeholders in examples and read secrets from OCI Vault
or the environment at runtime. The `.gitignore` covers the obvious files, but
it cannot catch an OCID pasted into a Markdown table.

## Licensing

Contributions are accepted under the repository's Apache-2.0 license
(inbound = outbound). There is no CLA. OpenHuman itself is GPL-3.0; this
repository does not vendor or modify its code. The VM downloads the upstream
release binary at boot.
