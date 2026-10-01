locals {
  compartment_id   = time_sleep.compartment.triggers["id"]
  compartment_name = oci_identity_compartment.this.name

  vcn_cidr            = "10.80.0.0/16"
  public_subnet_cidr  = "10.80.0.0/24"
  private_subnet_cidr = "10.80.1.0/24"

  osn_services = data.oci_core_services.all.services[0]

  domain = one([
    for d in data.oci_identity_domains.all.domains : d
    if d.display_name == var.identity_domain_name
  ])

  # TLS (one-way) connect descriptor for the LOW service of the ADB.
  adb_tls_low = one([
    for p in oci_database_autonomous_database.this.connection_strings[0].profiles : p.value
    if p.tls_authentication == "SERVER" && p.consumer_group == "LOW"
  ])

  genai_inference_url = "https://inference.generativeai.${var.genai_region}.oci.oraclecloud.com/openai/v1"

  use_generated_tls = var.tls_certificate_pem == ""

  common_tags = {
    project = "openhuman-oci"
    managed = "terraform"
  }
}
