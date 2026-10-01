# Service log for MCP server invocations. Authorization failures (-32007)
# only name the missing permission here.
resource "oci_logging_log_group" "this" {
  compartment_id = local.compartment_id
  display_name   = "${var.name_prefix}-logs"
  description    = "OpenHuman pilot logs"
  freeform_tags  = local.common_tags
}

resource "oci_logging_log" "mcp_invoke" {
  display_name       = "${var.name_prefix}-mcp-invoke"
  log_group_id       = oci_logging_log_group.this.id
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = 30

  configuration {
    compartment_id = local.compartment_id

    source {
      category    = "invoke"
      resource    = oci_database_tools_database_tools_mcp_server.adb.id
      service     = "dbtools"
      source_type = "OCISERVICE"
    }
  }

  freeform_tags = local.common_tags
}

output "log_group_id" {
  value = oci_logging_log_group.this.id
}
