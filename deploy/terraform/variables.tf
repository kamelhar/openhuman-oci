# ---- account / auth -------------------------------------------------------

variable "oci_profile" {
  description = "Profile name in ~/.oci/config used by the OCI provider (API-key auth)."
  type        = string
  default     = "DEFAULT"
}

variable "tenancy_ocid" {
  description = "OCID of the tenancy. Used for IAM resources and tenancy-scoped data sources."
  type        = string
}

variable "admin_user_ocid" {
  description = "OCID of the IAM user who will invoke the MCP server (added to the MCP users group). Usually the same user as the OCI profile."
  type        = string
}

variable "identity_domain_name" {
  description = "Display name of the identity domain that owns the MCP server and the MCP users group."
  type        = string
  default     = "Default"
}

variable "region" {
  description = "Region for everything except Generative AI."
  type        = string
  default     = "ca-toronto-1"
}

variable "genai_region" {
  description = "Region of the OCI Generative AI endpoint the core talks to."
  type        = string
  default     = "us-chicago-1"
}

# ---- naming / access -------------------------------------------------------

variable "name_prefix" {
  description = "Prefix for resource names and the compartment name."
  type        = string
  default     = "openhuman"
}

variable "allowed_client_cidrs" {
  description = "CIDRs allowed to reach the load balancer (443), the bastion, and the database ACL. Use your own public IP as /32."
  type        = list(string)

  validation {
    condition     = length(var.allowed_client_cidrs) > 0 && alltrue([for c in var.allowed_client_cidrs : can(cidrhost(c, 0))])
    error_message = "allowed_client_cidrs must be a non-empty list of CIDR blocks."
  }
}

variable "ssh_public_key" {
  description = "SSH public key installed on the VM (admin access through the bastion only)."
  type        = string
}

# ---- compute ---------------------------------------------------------------

variable "vm_ocpus" {
  description = "Ampere A1 OCPUs for the core VM. Always Free allows 4 across the tenancy."
  type        = number
  default     = 3
}

variable "vm_memory_gbs" {
  description = "Memory for the core VM. Always Free allows 24 GB across the tenancy."
  type        = number
  default     = 18
}

variable "boot_volume_gbs" {
  description = "Boot volume size. Counts toward the 200 GB Always Free block storage allowance."
  type        = number
  default     = 50
}

variable "workspace_volume_gbs" {
  description = "Block volume for the OpenHuman workspace (memory DB, vault, sessions). Survives VM recreation."
  type        = number
  default     = 50
}

# ---- OpenHuman -------------------------------------------------------------

variable "openhuman_version" {
  description = "Upstream release whose aarch64 core tarball is wrapped into the container on the VM."
  type        = string
  default     = "0.64.10"
}

variable "vm_assets_base_url" {
  description = "Base URL the VM downloads its bootstrap assets from (deploy/vm in this repo)."
  type        = string
  default     = "https://raw.githubusercontent.com/kamelhar/openhuman-oci"
}

variable "vm_assets_ref" {
  description = "Git ref of this repo to fetch VM assets from."
  type        = string
  default     = "main"
}

variable "genai_chat_model" {
  description = "OCI Generative AI model id used for chat, reasoning, agentic, coding and vision roles via the OpenAI-compatible endpoint."
  type        = string
  default     = "openai.gpt-4.1"
}

variable "genai_temperature" {
  description = "Sampling temperature pinned on every agent role (provider-string suffix). Low values make the prompt-guided tool protocol more reliable. Empty string leaves the model default."
  type        = string
  default     = "0.2"
}

variable "inference_mode" {
  description = "local-openai: OCI GenAI wired as a caller-owned OpenAI-compatible runtime, no TinyHumans session needed (default). byok-cloud: custom cloud route, requires a TinyHumans API key."
  type        = string
  default     = "local-openai"

  validation {
    condition     = contains(["local-openai", "byok-cloud"], var.inference_mode)
    error_message = "inference_mode must be local-openai or byok-cloud."
  }
}

variable "tinyhumans_backend_url" {
  description = "TinyHumans backend URL. The headless core expects it to be set even when inference is BYOK (Shape A)."
  type        = string
  default     = "https://api.tinyhumans.ai"
}

variable "tinyhumans_api_key" {
  description = "Optional TinyHumans API key for managed features (integrations, voice). Leave empty for BYOK-only."
  type        = string
  default     = ""
  sensitive   = true
}

# ---- load balancer ---------------------------------------------------------

variable "allowed_paths" {
  description = "Exact request paths the load balancer forwards to the core. Everything else is rejected with 403."
  type        = list(string)
  default     = ["/rpc", "/health", "/events"]
}

variable "lb_hostname" {
  description = "DNS name placed in the self-signed certificate (in addition to the LB public IP)."
  type        = string
  default     = "openhuman-core.local"
}

variable "tls_certificate_pem" {
  description = "Optional real TLS certificate (PEM). When empty a local CA and leaf are generated."
  type        = string
  default     = ""
}

variable "tls_private_key_pem" {
  description = "Private key for tls_certificate_pem."
  type        = string
  default     = ""
  sensitive   = true
}

variable "tls_ca_certificate_pem" {
  description = "CA chain for tls_certificate_pem."
  type        = string
  default     = ""
}

# ---- database / MCP --------------------------------------------------------

variable "adb_db_name" {
  description = "Autonomous Database name (max 14 chars for Always Free, alphanumeric)."
  type        = string
  default     = "openhuman"
}

variable "adb_db_version" {
  description = "Autonomous Database version. 26ai is available as Always Free."
  type        = string
  default     = "26ai"
}

variable "mcp_access_token_expiry_seconds" {
  type    = number
  default = 3600
}

variable "mcp_refresh_token_expiry_seconds" {
  type    = number
  default = 86400
}

variable "bastion_client_cidrs" {
  description = "CIDRs allowed to open bastion sessions. Defaults to allowed_client_cidrs. Set wider if your SSH egress IP differs from your HTTPS egress IP (split-tunnel VPNs); sessions are still key-authenticated."
  type        = list(string)
  default     = []
}

variable "enable_mcp_oauth_client" {
  description = "Experimental: create a client-credentials OAuth client for the MCP server. IAM could not authorize it as of 2026-10-01; the supported path is a user token stored in Vault."
  type        = bool
  default     = false
}

variable "enable_bastion" {
  description = "Create an OCI Bastion for admin access to the private subnet."
  type        = bool
  default     = true
}
