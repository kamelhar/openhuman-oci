resource "oci_kms_vault" "this" {
  compartment_id = local.compartment_id
  display_name   = "${var.name_prefix}-vault"
  vault_type     = "DEFAULT"
  freeform_tags  = local.common_tags
}

resource "oci_kms_key" "this" {
  compartment_id      = local.compartment_id
  display_name        = "${var.name_prefix}-key"
  management_endpoint = oci_kms_vault.this.management_endpoint
  protection_mode     = "SOFTWARE"

  key_shape {
    algorithm = "AES"
    length    = 32
  }
}

# ---- secret values -----------------------------------------------------------

resource "random_id" "core_token" {
  byte_length = 32
}

resource "random_password" "adb_admin" {
  length           = 24
  special          = true
  override_special = "_#"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 1
}

# ---- secrets ---------------------------------------------------------------

resource "oci_vault_secret" "core_token" {
  compartment_id = local.compartment_id
  vault_id       = oci_kms_vault.this.id
  key_id         = oci_kms_key.this.id
  secret_name    = "${var.name_prefix}-core-token"
  description    = "Bearer token for the OpenHuman core /rpc endpoint"

  secret_content {
    content_type = "BASE64"
    content      = base64encode(random_id.core_token.hex)
  }
}

resource "oci_vault_secret" "adb_admin_password" {
  compartment_id = local.compartment_id
  vault_id       = oci_kms_vault.this.id
  key_id         = oci_kms_key.this.id
  secret_name    = "${var.name_prefix}-adb-admin-password"
  description    = "ADMIN password of the Autonomous Database (used by the Database Tools connection)"

  secret_content {
    content_type = "BASE64"
    content      = base64encode(random_password.adb_admin.result)
  }
}

# Filled in by deploy/scripts/01-genai-api-key.sh after apply. Terraform only
# creates the placeholder and never reads the value back.
resource "oci_vault_secret" "genai_api_key" {
  compartment_id = local.compartment_id
  vault_id       = oci_kms_vault.this.id
  key_id         = oci_kms_key.this.id
  secret_name    = "${var.name_prefix}-genai-api-key"
  description    = "OCI Generative AI API key used by the core for the OpenAI-compatible endpoint"

  secret_content {
    content_type = "BASE64"
    content      = base64encode("PENDING")
  }

  lifecycle {
    ignore_changes = [secret_content]
  }
}

resource "oci_vault_secret" "tinyhumans_api_key" {
  compartment_id = local.compartment_id
  vault_id       = oci_kms_vault.this.id
  key_id         = oci_kms_key.this.id
  secret_name    = "${var.name_prefix}-tinyhumans-api-key"
  description    = "Optional TinyHumans API key (NONE when BYOK-only)"

  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.tinyhumans_api_key != "" ? var.tinyhumans_api_key : "NONE")
  }
}
