# Authenticates with an API-key profile from ~/.oci/config. The profile name is
# an input so nothing account-specific lives in the repo.
provider "oci" {
  auth                = "APIKey"
  config_file_profile = var.oci_profile
  region              = var.region
}
