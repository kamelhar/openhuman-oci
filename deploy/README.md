# Deploying the pilot

Everything here targets the Shape A pilot described in `../docs/ARCHITECTURE.md`
and validated in `../docs/PILOT-ACCOUNT-VALIDATION.md`: one Always Free Ampere
VM running the upstream `openhuman-core` binary in a container, OCI Generative
AI for inference, Ollama for embeddings, an Always Free Autonomous Database
reached by agents through the managed Database Tools MCP Server.

## Prerequisites

- Terraform >= 1.5, OCI CLI, `jq`, Python 3 with `oracledb` and `oci` for the demo seed.
- An API-key profile in `~/.oci/config` with admin rights on the tenancy.
- Your public IP (for `allowed_client_cidrs`) and an SSH public key.
- If your shell exports `OCI_CLI_AUTH=security_token`, the scripts override it with `api_key`.

## Steps

```bash
cd deploy/terraform
cp terraform.tfvars.example terraform.tfvars   # fill in, never commit
terraform init && terraform plan
terraform apply

cd ../scripts
./01-genai-api-key.sh          # mints the GenAI API key, stores it in Vault
./02-trust-lb-cert.sh          # trusts the generated CA on macOS
# identity domain console: My profile -> Tokens and keys -> My access tokens ->
#   Invokes other APIs -> choose the MCP server app -> download tokens.tok
./03-register-mcp.sh ~/Downloads/tokens.tok
python3 04-seed-demo-data.py
```

Then open the OpenHuman desktop app, use the Advanced panel on the sign-in
screen, and set the custom core RPC URL from `terraform output core_rpc_url`
with the core token from Vault.

## What gets created

| Resource | Notes |
| --- | --- |
| Compartment, VCN, public + private subnets, IGW, NAT, service gateway | all free |
| NSGs: LB (443 from your CIDRs), core (7788 from LB, 22 from subnet), Database Tools PE | |
| Vault + AES key + 4 secrets | core token, ADB admin password, GenAI API key (placeholder), TinyHumans key (optional) |
| Autonomous Database 26ai, Always Free, TLS without wallet, ACL = VCN + your CIDRs | |
| Database Tools private endpoint, connection (ADMIN), MCP server (resource principal) | |
| Identity domain group for MCP users, dynamic group for the VM, one policy | |
| Ampere A1 VM 3 OCPU / 18 GB, Ubuntu 24.04, 50 GB boot + 50 GB workspace volume | |
| Flexible LB 10 Mbps, reserved public IP, generated CA + leaf cert, path allowlist | |
| OCI Bastion (optional) | admin only |

## Teardown

`terraform destroy`. The compartment is created with `enable_delete`, so it goes too.
The GenAI API key created by the script is not in state; delete it with
`oci generative-ai api-key delete` or from the console.
