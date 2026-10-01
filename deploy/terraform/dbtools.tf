data "oci_database_tools_database_tools_endpoint_services" "this" {
  compartment_id = var.tenancy_ocid
  name           = "DATABASE_TOOLS"
}

# Gives the Database Tools runtime a VNIC in the private subnet, so its traffic
# to the ADB public endpoint goes through the service gateway and matches the
# VCN entry in the ADB access list.
resource "oci_database_tools_database_tools_private_endpoint" "this" {
  compartment_id      = local.compartment_id
  display_name        = "${var.name_prefix}-dbtools-pe"
  endpoint_service_id = data.oci_database_tools_database_tools_endpoint_services.this.database_tools_endpoint_service_collection[0].items[0].id
  subnet_id           = oci_core_subnet.private.id
  nsg_ids             = [oci_core_network_security_group.dbtools_pe.id]
  freeform_tags       = local.common_tags
}

resource "oci_database_tools_database_tools_connection" "adb" {
  compartment_id    = local.compartment_id
  display_name      = "${var.name_prefix}-adb-admin"
  type              = "ORACLE_DATABASE"
  user_name         = "ADMIN"
  connection_string = local.adb_tls_low

  user_password {
    value_type = "SECRETID"
    secret_id  = oci_vault_secret.adb_admin_password.id
  }

  related_resource {
    entity_type = "AUTONOMOUSDATABASE"
    identifier  = oci_database_autonomous_database.this.id
  }

  private_endpoint_id = oci_database_tools_database_tools_private_endpoint.this.id
  runtime_support     = "SUPPORTED"
  runtime_identity    = "RESOURCE_PRINCIPAL"

  advanced_properties = {
    "oracle.net.ssl_server_dn_match" = "true"
  }

  freeform_tags = local.common_tags
}

resource "oci_database_tools_database_tools_mcp_server" "adb" {
  compartment_id               = local.compartment_id
  database_tools_connection_id = oci_database_tools_database_tools_connection.adb.id
  display_name                 = "${var.name_prefix}-adb-mcp"
  description                  = "Managed MCP server exposing SQL tools over the OpenHuman pilot database"
  domain_id                    = local.domain.id
  type                         = "DEFAULT"
  runtime_identity             = "RESOURCE_PRINCIPAL"

  storage {
    type = "NONE"
  }

  access_token_expiry_in_seconds  = var.mcp_access_token_expiry_seconds
  refresh_token_expiry_in_seconds = var.mcp_refresh_token_expiry_seconds

  freeform_tags = local.common_tags
}
