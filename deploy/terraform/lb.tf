# Reserved IP first, so the generated certificate can carry it as a SAN.
resource "oci_core_public_ip" "lb" {
  compartment_id = local.compartment_id
  display_name   = "${var.name_prefix}-lb-ip"
  lifetime       = "RESERVED"
  freeform_tags  = local.common_tags
}

# ---- generated TLS (default) -------------------------------------------------

resource "tls_private_key" "ca" {
  count       = local.use_generated_tls ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "ca" {
  count             = local.use_generated_tls ? 1 : 0
  private_key_pem   = tls_private_key.ca[0].private_key_pem
  is_ca_certificate = true

  subject {
    common_name  = "${var.name_prefix}-oci local CA"
    organization = "openhuman-oci"
  }

  validity_period_hours = 24 * 365 * 3
  allowed_uses          = ["cert_signing", "crl_signing", "digital_signature"]
}

resource "tls_private_key" "leaf" {
  count       = local.use_generated_tls ? 1 : 0
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_cert_request" "leaf" {
  count           = local.use_generated_tls ? 1 : 0
  private_key_pem = tls_private_key.leaf[0].private_key_pem
  dns_names       = [var.lb_hostname]
  ip_addresses    = [oci_core_public_ip.lb.ip_address]

  subject {
    common_name  = var.lb_hostname
    organization = "openhuman-oci"
  }
}

resource "tls_locally_signed_cert" "leaf" {
  count              = local.use_generated_tls ? 1 : 0
  cert_request_pem   = tls_cert_request.leaf[0].cert_request_pem
  ca_private_key_pem = tls_private_key.ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca[0].cert_pem

  validity_period_hours = 24 * 365
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

locals {
  lb_cert_pem = local.use_generated_tls ? tls_locally_signed_cert.leaf[0].cert_pem : var.tls_certificate_pem
  lb_key_pem  = local.use_generated_tls ? tls_private_key.leaf[0].private_key_pem : var.tls_private_key_pem
  lb_ca_pem   = local.use_generated_tls ? tls_self_signed_cert.ca[0].cert_pem : var.tls_ca_certificate_pem
}

# ---- load balancer -----------------------------------------------------------

resource "oci_load_balancer_load_balancer" "this" {
  compartment_id             = local.compartment_id
  display_name               = "${var.name_prefix}-lb"
  shape                      = "flexible"
  subnet_ids                 = [oci_core_subnet.public.id]
  is_private                 = false
  network_security_group_ids = [oci_core_network_security_group.lb.id]

  shape_details {
    minimum_bandwidth_in_mbps = 10
    maximum_bandwidth_in_mbps = 10
  }

  reserved_ips {
    id = oci_core_public_ip.lb.id
  }

  freeform_tags = local.common_tags
}

resource "oci_load_balancer_certificate" "this" {
  load_balancer_id   = oci_load_balancer_load_balancer.this.id
  certificate_name   = "${var.name_prefix}-cert"
  public_certificate = local.lb_cert_pem
  private_key        = local.lb_key_pem
  ca_certificate     = local.lb_ca_pem

  lifecycle {
    create_before_destroy = true
  }
}

resource "oci_load_balancer_backend_set" "core" {
  load_balancer_id = oci_load_balancer_load_balancer.this.id
  name             = "core"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol          = "HTTP"
    port              = 7788
    url_path          = "/health"
    return_code       = 200
    interval_ms       = 30000
    timeout_in_millis = 5000
    retries           = 3
  }
}

resource "oci_load_balancer_backend" "core" {
  load_balancer_id = oci_load_balancer_load_balancer.this.id
  backendset_name  = oci_load_balancer_backend_set.core.name
  ip_address       = oci_core_instance.core.private_ip
  port             = 7788
}

# Only the listed paths reach the core. Anything else is answered 403 by the LB.
resource "oci_load_balancer_rule_set" "path_allowlist" {
  load_balancer_id = oci_load_balancer_load_balancer.this.id
  name             = "path_allowlist"

  dynamic "items" {
    for_each = toset(var.allowed_paths)
    content {
      action      = "ALLOW"
      description = "allow ${items.value}"

      conditions {
        attribute_name  = "PATH"
        attribute_value = items.value
        operator        = "EXACT_MATCH"
      }
    }
  }
}

resource "oci_load_balancer_listener" "https" {
  load_balancer_id         = oci_load_balancer_load_balancer.this.id
  name                     = "https"
  default_backend_set_name = oci_load_balancer_backend_set.core.name
  port                     = 443
  protocol                 = "HTTP"
  rule_set_names           = [oci_load_balancer_rule_set.path_allowlist.name]

  ssl_configuration {
    certificate_name        = oci_load_balancer_certificate.this.certificate_name
    verify_peer_certificate = false
    protocols               = ["TLSv1.2", "TLSv1.3"]
  }

  connection_configuration {
    idle_timeout_in_seconds = 1200
  }
}
