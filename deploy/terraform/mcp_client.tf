# EXPERIMENTAL, off by default. A confidential OAuth client for the core itself,
# minting client-credentials tokens for the MCP server's audience. Finding
# (2026-10-01): the MCP endpoint accepts the token, but IAM evaluates the caller
# as principal type "user" with the domain-app OCID, and no policy form matched
# it (request.principal.id, request.user.id, or an unconditional any-user grant
# all return -32007 DATABASE_TOOLS_MCP_SERVER_INVOKE). Oracle's supported shapes
# are user tokens: personal access token, OAuth sign-in, or a trusted client
# acting on behalf of a user (jwt-bearer). Kept for a future on-behalf-of attempt.

locals {
  mcp_scope_fqs = "urn:opc:dbtools:mcpserver:${oci_database_tools_database_tools_mcp_server.adb.id}mcp:all"
  mcp_token_url = "${local.domain.url}/oauth2/v1/token"
}

resource "oci_identity_domains_app" "mcp_client" {
  count = var.enable_mcp_oauth_client ? 1 : 0

  idcs_endpoint = local.domain.url
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:App"]
  display_name  = "${var.name_prefix}-core-mcp-client"
  description   = "OpenHuman core: client-credentials client for the Database Tools MCP Server"

  based_on_template {
    value = "CustomWebAppTemplateId"
  }

  active             = true
  is_oauth_client    = true
  client_type        = "confidential"
  allowed_grants     = ["client_credentials"]
  allowed_operations = ["introspect"]
  trust_scope        = "Explicit"
  bypass_consent     = true
  force_delete       = true # apps must be inactive before deletion; let the provider handle it

  allowed_scopes {
    fqs = local.mcp_scope_fqs
  }

  lifecycle {
    ignore_changes = [schemas]
  }
}

# The client acts as itself, so it needs the MCP_Operator app role directly.
resource "oci_identity_domains_grant" "mcp_client_operator" {
  count = var.enable_mcp_oauth_client ? 1 : 0

  idcs_endpoint   = local.domain.url
  schemas         = ["urn:ietf:params:scim:schemas:oracle:idcs:Grant"]
  grant_mechanism = "ADMINISTRATOR_TO_APP"

  grantee {
    type  = "App"
    value = oci_identity_domains_app.mcp_client[0].id
  }

  app {
    value = oci_database_tools_database_tools_mcp_server.adb.domain_app_id
  }

  entitlement {
    attribute_name  = "appRoles"
    attribute_value = data.oci_identity_domains_app_roles.mcp_operator.app_roles[0].id
  }
}

resource "oci_vault_secret" "mcp_client_secret" {
  count = var.enable_mcp_oauth_client ? 1 : 0

  compartment_id = local.compartment_id
  vault_id       = oci_kms_vault.this.id
  key_id         = oci_kms_key.this.id
  secret_name    = "${var.name_prefix}-mcp-client-secret"
  description    = "Client secret of the core's OAuth client for the Database Tools MCP Server"

  secret_content {
    content_type = "BASE64"
    # The identity domain generates the secret; Terraform reads it back once.
    content = base64encode(oci_identity_domains_app.mcp_client[0].client_secret)
  }
}

output "mcp_client" {
  description = "Client-credentials settings (experimental, see enable_mcp_oauth_client)."
  value = var.enable_mcp_oauth_client ? {
    client_id = oci_identity_domains_app.mcp_client[0].name
    token_url = local.mcp_token_url
    scope     = local.mcp_scope_fqs
    secret_id = oci_vault_secret.mcp_client_secret[0].id
  } : null
}
