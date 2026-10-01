output "compartment_id" {
  value = local.compartment_id
}

output "lb_public_ip" {
  value = oci_core_public_ip.lb.ip_address
}

output "core_rpc_url" {
  description = "Point the desktop app (external mode) at this URL."
  value       = "https://${oci_core_public_ip.lb.ip_address}/rpc"
}

output "lb_ca_certificate_pem" {
  description = "CA to trust on the client when using the generated certificate."
  value       = local.lb_ca_pem
}

output "core_instance_id" {
  value = oci_core_instance.core.id
}

output "core_private_ip" {
  value = oci_core_instance.core.private_ip
}

output "bastion_id" {
  value = var.enable_bastion ? oci_bastion_bastion.this[0].id : null
}

output "vault_id" {
  value = oci_kms_vault.this.id
}

output "secret_ids" {
  value = {
    core_token         = oci_vault_secret.core_token.id
    adb_admin_password = oci_vault_secret.adb_admin_password.id
    genai_api_key      = oci_vault_secret.genai_api_key.id
    tinyhumans_api_key = oci_vault_secret.tinyhumans_api_key.id
    mcp_user_token     = oci_vault_secret.mcp_user_token.id
  }
}

output "genai" {
  value = {
    region        = var.genai_region
    inference_url = local.genai_inference_url
    chat_model    = var.genai_chat_model
  }
}

output "adb" {
  value = {
    id                     = oci_database_autonomous_database.this.id
    display_name           = oci_database_autonomous_database.this.display_name
    tls_low_connect_string = local.adb_tls_low
  }
}

output "mcp_server" {
  value = {
    id            = oci_database_tools_database_tools_mcp_server.adb.id
    endpoints     = oci_database_tools_database_tools_mcp_server.adb.endpoints
    domain_app_id = oci_database_tools_database_tools_mcp_server.adb.domain_app_id
    users_group   = oci_identity_domains_group.mcp_users.display_name
  }
}

output "next_steps" {
  value = <<-EOT
    1. deploy/scripts/01-genai-api-key.sh      create the GenAI API key and store it in Vault
    2. deploy/scripts/02-trust-lb-cert.sh      trust the generated CA on this Mac
    3. generate a Personal Access Token for the MCP server app in the identity domain console,
       then deploy/scripts/03-register-mcp.sh  register the MCP server in OpenHuman
    4. deploy/scripts/04-seed-demo-data.py     create the demo ORDERS table
    5. desktop app -> Advanced -> custom core RPC URL: ${"https://${oci_core_public_ip.lb.ip_address}/rpc"}
  EOT
}
