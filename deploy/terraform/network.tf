data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_core_vcn" "this" {
  compartment_id = local.compartment_id
  cidr_blocks    = [local.vcn_cidr]
  display_name   = "${var.name_prefix}-vcn"
  dns_label      = "openhuman"
  freeform_tags  = local.common_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-igw"
  enabled        = true
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-nat"
}

resource "oci_core_service_gateway" "this" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-sgw"

  services {
    service_id = local.osn_services.id
  }
}

resource "oci_core_route_table" "public" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-rt-public"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.this.id
  }
}

resource "oci_core_route_table" "private" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-rt-private"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.this.id
  }

  route_rules {
    destination       = local.osn_services.cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.this.id
  }
}

# Security lists stay closed on ingress; NSGs open exactly what is needed.
resource "oci_core_security_list" "closed" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "${var.name_prefix}-sl-closed"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }
}

resource "oci_core_subnet" "public" {
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = local.public_subnet_cidr
  display_name               = "${var.name_prefix}-public"
  dns_label                  = "pub"
  route_table_id             = oci_core_route_table.public.id
  security_list_ids          = [oci_core_security_list.closed.id]
  prohibit_public_ip_on_vnic = false
}

resource "oci_core_subnet" "private" {
  compartment_id             = local.compartment_id
  vcn_id                     = oci_core_vcn.this.id
  cidr_block                 = local.private_subnet_cidr
  display_name               = "${var.name_prefix}-private"
  dns_label                  = "priv"
  route_table_id             = oci_core_route_table.private.id
  security_list_ids          = [oci_core_security_list.closed.id]
  prohibit_public_ip_on_vnic = true
}
