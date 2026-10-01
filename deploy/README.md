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
#   "Invokes other APIs" -> select the MCP server app (named <prefix>-adb-mcp) ->
#   expiry -> Download token (tokens.tok)
./03-register-mcp.sh ~/Downloads/tokens.tok   # stores it in Vault; the VM registers the server
python3 04-seed-demo-data.py   # from an IP in the ADB access list; otherwise run it on the VM
```

Smoke test the core from your machine (token from Vault, CA from `terraform output`):

```bash
curl --cacert ca.pem -X POST "$(terraform -chdir=../terraform output -raw core_rpc_url)" \
  -H "Authorization: Bearer $CORE_TOKEN" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"openhuman.inference_agent_chat_simple","params":{"message":"Reply with exactly: OCI pilot OK"}}'
```

Then open the OpenHuman desktop app, use the Advanced panel on the sign-in
screen, and set the custom core RPC URL from `terraform output core_rpc_url`
with the core token from Vault.

## What gets created

| Resource | Notes |
| --- | --- |
| Compartment, VCN, public + private subnets, IGW, NAT, service gateway | all free |
| NSGs: LB (443 from your CIDRs), core (7788 from LB, 22 from subnet), Database Tools PE | |
| Vault + AES key + 5 secrets | core token, ADB admin password, GenAI API key and MCP user token (placeholders filled by scripts), TinyHumans key (optional) |
| Autonomous Database 26ai, Always Free, TLS without wallet, ACL = VCN + your CIDRs | |
| Database Tools private endpoint, connection (ADMIN), MCP server (resource principal) | |
| Identity domain group for MCP users, dynamic group for the VM, one policy | |
| Ampere A1 VM 3 OCPU / 18 GB, Ubuntu 24.04, 50 GB boot + 50 GB workspace volume | |
| Flexible LB 10 Mbps, reserved public IP, generated CA + leaf cert, path allowlist | |
| OCI Bastion (optional) | admin only; set `bastion_client_cidrs` wider if your SSH egress IP differs from your HTTPS egress IP |
| Log group + MCP invoke service log | the only place -32007 authorization failures name the missing permission |

## Teardown

`terraform destroy`. The compartment is created with `enable_delete`, so it goes too.
The GenAI API key created by the script is not in state; delete it with
`oci generative-ai api-key delete` or from the console.
