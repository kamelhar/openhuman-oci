resource "oci_identity_compartment" "this" {
  compartment_id = var.tenancy_ocid
  name           = var.name_prefix
  description    = "OpenHuman on OCI pilot (Always Free)"
  enable_delete  = true
  freeform_tags  = local.common_tags
}

# New compartments take a moment to become visible to other services.
resource "time_sleep" "compartment" {
  depends_on      = [oci_identity_compartment.this]
  create_duration = "60s"

  triggers = {
    id = oci_identity_compartment.this.id
  }
}
