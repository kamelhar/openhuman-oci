# ---- NSG: load balancer ----------------------------------------------------

resource "oci_core_network_security_group" "lb" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-nsg-lb"
}

resource "oci_core_network_security_group_security_rule" "lb_in_https" {
  for_each                  = toset(var.allowed_client_cidrs)
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = each.value
  source_type               = "CIDR_BLOCK"
  description               = "HTTPS from an allowed client"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "lb_out_core" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "EGRESS"
  protocol                  = "6"
  destination               = oci_core_network_security_group.core.id
  destination_type          = "NETWORK_SECURITY_GROUP"
  description               = "To the core RPC port"

  tcp_options {
    destination_port_range {
      min = 7788
      max = 7788
    }
  }
}

# ---- NSG: core VM ----------------------------------------------------------

resource "oci_core_network_security_group" "core" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-nsg-core"
}

resource "oci_core_network_security_group_security_rule" "core_in_rpc" {
  network_security_group_id = oci_core_network_security_group.core.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.lb.id
  source_type               = "NETWORK_SECURITY_GROUP"
  description               = "RPC from the load balancer only"

  tcp_options {
    destination_port_range {
      min = 7788
      max = 7788
    }
  }
}

resource "oci_core_network_security_group_security_rule" "core_in_ssh" {
  network_security_group_id = oci_core_network_security_group.core.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = local.private_subnet_cidr
  source_type               = "CIDR_BLOCK"
  description               = "SSH from the bastion (same subnet)"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}

resource "oci_core_network_security_group_security_rule" "core_out_all" {
  network_security_group_id = oci_core_network_security_group.core.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Egress via NAT (GenAI, GitHub, TinyHumans, registries)"
}

# ---- NSG: Database Tools private endpoint ----------------------------------

resource "oci_core_network_security_group" "dbtools_pe" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-nsg-dbtools-pe"
}

resource "oci_core_network_security_group_security_rule" "dbtools_pe_out_all" {
  network_security_group_id = oci_core_network_security_group.dbtools_pe.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
  description               = "Reach the ADB endpoint through the service gateway"
}
