# Always Free Autonomous Database. TLS without a wallet is allowed because the
# ACL restricts clients to this VCN (via the service gateway) and the operator.
resource "oci_database_autonomous_database" "this" {
  compartment_id = local.compartment_id
  db_name        = var.adb_db_name
  display_name   = "${var.name_prefix}-adb"
  db_workload    = "OLTP"
  db_version     = var.adb_db_version
  is_free_tier   = true

  cpu_core_count           = 1
  data_storage_size_in_tbs = 1
  admin_password           = random_password.adb_admin.result
  license_model            = "LICENSE_INCLUDED"

  is_mtls_connection_required = false
  whitelisted_ips             = concat([oci_core_vcn.this.id], var.allowed_client_cidrs)

  freeform_tags = local.common_tags
}
