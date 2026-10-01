data "oci_core_images" "ubuntu_arm" {
  compartment_id           = var.tenancy_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "core" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = local.compartment_id
  display_name        = "${var.name_prefix}-core"
  shape               = "VM.Standard.A1.Flex"

  shape_config {
    ocpus         = var.vm_ocpus
    memory_in_gbs = var.vm_memory_gbs
  }

  source_details {
    source_type             = "image"
    source_id               = data.oci_core_images.ubuntu_arm.images[0].id
    boot_volume_size_in_gbs = var.boot_volume_gbs
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.private.id
    assign_public_ip = false
    hostname_label   = "core"
    nsg_ids          = [oci_core_network_security_group.core.id]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data = base64encode(templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
      assets_base_url        = "${var.vm_assets_base_url}/${var.vm_assets_ref}/deploy/vm"
      openhuman_version      = var.openhuman_version
      oci_region             = var.region
      genai_inference_url    = local.genai_inference_url
      genai_chat_model       = var.genai_chat_model
      inference_mode         = var.inference_mode
      tinyhumans_backend_url = var.tinyhumans_backend_url
      secret_core_token      = oci_vault_secret.core_token.id
      secret_genai_api_key   = oci_vault_secret.genai_api_key.id
      secret_tinyhumans_key  = oci_vault_secret.tinyhumans_api_key.id
    }))
  }

  agent_config {
    is_management_disabled = false
    is_monitoring_disabled = false
  }

  freeform_tags = local.common_tags

  lifecycle {
    # Image refreshes and cloud-init edits must not recreate the VM.
    ignore_changes = [source_details[0].source_id, metadata["user_data"]]
  }
}

resource "oci_core_volume" "workspace" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = local.compartment_id
  display_name        = "${var.name_prefix}-workspace"
  size_in_gbs         = var.workspace_volume_gbs
  freeform_tags       = local.common_tags
}

resource "oci_core_volume_attachment" "workspace" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.core.id
  volume_id       = oci_core_volume.workspace.id
  device          = "/dev/oracleoci/oraclevdb"
}
