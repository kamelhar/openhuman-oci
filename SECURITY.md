# Security

## Reporting

Use GitHub's private vulnerability reporting on this repository, or open an
issue without exploit details and ask for a private channel. Problems in
OpenHuman itself go to its [security policy](https://github.com/tinyhumansai/openhuman/blob/main/SECURITY.md);
problems in OCI services go to Oracle support.

## What this deployment exposes

- One public load balancer on 443, restricted by network security group to the
  CIDRs you list in `allowed_client_cidrs`. It forwards only `/rpc`, `/health`
  and `/events`; every other path gets an empty backend.
- `/rpc` requires the core bearer token. In upstream's current build `/health`
  and `/events` are unauthenticated, and `/events` carries agent activity. The
  CIDR allowlist is the control for that; do not open the load balancer to the
  world.
- The core VM has no public IP. Admin access is through OCI Bastion only.
- The Autonomous Database accepts TLS without a wallet, but only from the VCN
  (through the service gateway) and from `allowed_client_cidrs`.

## Secrets

All secrets live in OCI Vault: core bearer token, database ADMIN password,
Generative AI API key, the MCP user token, the keyring master key, and an
optional TinyHumans key. The
VM reads them with its instance principal; nothing is baked into cloud-init or
images. Terraform state holds the generated values, so keep state private.

Inside the core, the headless build cannot reach an OS keychain. Release 0.64.10
has no way to receive the encrypted-file master key, so on it the pilot runs the
plaintext file keyring on the block volume (encrypted at rest by OCI, `0600`,
private subnet) and the VM is the secret boundary. Upstream PR #6935 adds
`OPENHUMAN_KEYRING_MASTER_KEY`; Terraform already generates that key into Vault
and `render_config.py` switches to the `encrypted_file` keyring on any newer
release (`keyring_backend = "auto"`), re-pushing the provider keys afterwards.

## Rotation

- Core token: new `random_id` via `terraform taint`, or set the Vault secret and
  let the render timer restart the core.
- GenAI API key: `deploy/scripts/01-genai-api-key.sh` creates a new key; revoke
  the old one in the console.
- MCP user token: generate a new personal access token and re-run
  `deploy/scripts/03-register-mcp.sh`.
