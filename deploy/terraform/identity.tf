data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_domains" "all" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_domains_users" "admin" {
  idcs_endpoint = local.domain.url
  user_filter   = "ocid eq \"${var.admin_user_ocid}\""
}

# Members of this group may invoke the MCP server.
resource "oci_identity_domains_group" "mcp_users" {
  idcs_endpoint = local.domain.url
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = "${var.name_prefix}-mcp-users"

  members {
    type  = "User"
    value = data.oci_identity_domains_users.admin.users[0].id
  }
}

# Instance principal for the core VM: lets it read its secrets from Vault.
resource "oci_identity_dynamic_group" "vm" {
  compartment_id = var.tenancy_ocid
  name           = "${var.name_prefix}-vm"
  description    = "OpenHuman core VM(s) in the ${local.compartment_name} compartment"
  matching_rule  = "ALL {instance.compartment.id = '${local.compartment_id}'}"
}

resource "oci_identity_policy" "compartment" {
  compartment_id = local.compartment_id
  name           = "${var.name_prefix}-policy"
  description    = "OpenHuman pilot: VM secrets, GenAI API keys, Database Tools MCP server"

  statements = [
    # VM reads its own secrets.
    "allow dynamic-group ${oci_identity_dynamic_group.vm.name} to read secret-bundles in compartment ${local.compartment_name}",

    # Any GenAI API key created in this compartment may call inference.
    "allow any-user to use generative-ai-family in compartment ${local.compartment_name} where ALL {request.principal.type='generativeaiapikey'}",

    # MCP: users invoke the server; the server uses the connection; the
    # connection reads the DB password. (Resource-principal / resource-principal
    # / password layout from the Database Tools MCP policy reference.)
    "allow group '${local.domain.display_name}'/'${oci_identity_domains_group.mcp_users.display_name}' to use database-tools-mcp-servers-invocation in compartment ${local.compartment_name}",
    "allow any-user to use database-tools-connections in compartment ${local.compartment_name} where request.principal.id = '${oci_database_tools_database_tools_mcp_server.adb.id}'",
    "allow any-user to read secret-bundles in compartment ${local.compartment_name} where request.principal.id = '${oci_database_tools_database_tools_connection.adb.id}'",
  ]
}
