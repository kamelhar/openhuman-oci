resource "oci_bastion_bastion" "this" {
  count                        = var.enable_bastion ? 1 : 0
  compartment_id               = local.compartment_id
  bastion_type                 = "STANDARD"
  name                         = "${var.name_prefix}bastion"
  target_subnet_id             = oci_core_subnet.private.id
  client_cidr_block_allow_list = length(var.bastion_client_cidrs) > 0 ? var.bastion_client_cidrs : var.allowed_client_cidrs
  max_session_ttl_in_seconds   = 10800
  freeform_tags                = local.common_tags
}
