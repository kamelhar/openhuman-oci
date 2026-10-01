# The MCP server registers itself as a resource-server application in the
# identity domain (domain_app_id is that app's SCIM id). Callers must hold one of its app roles; grant MCP_Operator
# to the MCP users group so members can invoke every tool in the toolset.

data "oci_identity_domains_app_roles" "mcp_operator" {
  idcs_endpoint   = local.domain.url
  app_role_filter = "app.value eq \"${oci_database_tools_database_tools_mcp_server.adb.domain_app_id}\" and displayName eq \"MCP_Operator\""
}

resource "oci_identity_domains_grant" "mcp_operator" {
  idcs_endpoint   = local.domain.url
  schemas         = ["urn:ietf:params:scim:schemas:oracle:idcs:Grant"]
  grant_mechanism = "ADMINISTRATOR_TO_GROUP"

  grantee {
    type  = "Group"
    value = oci_identity_domains_group.mcp_users.id
  }

  app {
    value = oci_database_tools_database_tools_mcp_server.adb.domain_app_id
  }

  entitlement {
    attribute_name  = "appRoles"
    attribute_value = data.oci_identity_domains_app_roles.mcp_operator.app_roles[0].id
  }
}
