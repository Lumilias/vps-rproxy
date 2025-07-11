resource "oci_core_instance" "atlas_instance" {
  count               = var.num_instances
  availability_domain = data.oci_identity_availability_domain.ad.name
  compartment_id      = var.compartment_ocid
  display_name        = format("%s${count.index}", replace(title(var.instance_name), "/\\s/", ""))
  shape               = var.instance_shape

  shape_config {
    ocpus         = var.instance_ocpus
    memory_in_gbs = var.instance_shape_config_memory_in_gbs
  }

  create_vnic_details {
    subnet_id                 = oci_core_subnet.atlas_subnet.id
    display_name              = format("%sVNIC", replace(title(var.instance_name), "/\\s/", ""))
    assign_public_ip          = true
    assign_private_dns_record = true
    hostname_label            = format("%s${count.index}", lower(replace(var.instance_name, "/\\s/", "")))
  }

  source_details {
    source_type = var.instance_source_type
    source_id   = var.instance_image_ocid[var.oci_region]
		boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  agent_config {
    plugins_config {
      desired_state = "ENABLED"
      name          = "Management Agent"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Monitoring"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "Compute Instance Run Command"
    }
    plugins_config {
      desired_state = "ENABLED"
      name          = "OS Management Hub Agent"
    }
  }

  metadata = {
    ssh_authorized_keys = file("pubkey.pub")
    user_data           = "${base64encode(data.template_file.cloud-config.rendered)}"
  }

  timeouts {
    create = "60m"
  }
}

resource "oci_core_vcn" "atlas_vcn" {
  cidr_block     = "10.1.0.0/16"
  compartment_id = var.compartment_ocid
  display_name   = format("%sVCN", replace(title(var.instance_name), "/\\s/", ""))
  dns_label      = format("%svcn", lower(replace(var.instance_name, "/\\s/", "")))
}

resource "oci_core_security_list" "atlas_security_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.atlas_vcn.id
  display_name   = format("%sSecurityList", replace(title(var.instance_name), "/\\s/", ""))

  # Allow outbound traffic on all ports for all protocols
  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = false
  }

  # Allow inbound traffic on all ports for all protocols
  ingress_security_rules {
    protocol  = "all"
    source    = "0.0.0.0/0"
    stateless = false
  }

  # Allow inbound icmp traffic of a specific type
  ingress_security_rules {
    protocol  = 1
    source    = "0.0.0.0/0"
    stateless = false

    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_internet_gateway" "atlas_internet_gateway" {
  compartment_id = var.compartment_ocid
  display_name   = format("%sIGW", replace(title(var.instance_name), "/\\s/", ""))
  vcn_id         = oci_core_vcn.atlas_vcn.id
}

resource "oci_core_default_route_table" "default_route_table" {
  manage_default_resource_id = oci_core_vcn.atlas_vcn.default_route_table_id
  display_name               = "DefaultRouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.atlas_internet_gateway.id
  }
}

resource "oci_core_subnet" "atlas_subnet" {
  availability_domain = data.oci_identity_availability_domain.ad.name
  cidr_block          = "10.1.20.0/24"
  display_name        = format("%sSubnet", replace(title(var.instance_name), "/\\s/", ""))
  dns_label           = format("%ssubnet", lower(replace(var.instance_name, "/\\s/", "")))
  security_list_ids   = [oci_core_security_list.atlas_security_list.id]
  compartment_id      = var.compartment_ocid
  vcn_id              = oci_core_vcn.atlas_vcn.id
  route_table_id      = oci_core_vcn.atlas_vcn.default_route_table_id
  dhcp_options_id     = oci_core_vcn.atlas_vcn.default_dhcp_options_id
}

# resource "null_resource" "remote-exec" {
#   count = var.auto_iptables ? var.num_instances : 0

#   connection {
#     agent       = false
#     timeout     = "30m"
#     host        = element(oci_core_instance.atlas_instance.*.public_ip, count.index)
#     user        = "ubuntu"
#     private_key = file(var.ssh_private_key)
#   }

#   provisioner "remote-exec" {
#     inline = [
#       "export DATE=$(date +%Y%m%d); sudo iptables -L > \"/home/ubuntu/iptables-$DATE.bak\"",
#       "sudo sh -c 'iptables -D INPUT -j REJECT --reject-with icmp-host-prohibited 2> /dev/null; iptables-save > /etc/iptables/rules.v4;'",
#       "sudo sh -c 'iptables -D FORWARD -j REJECT --reject-with icmp-host-prohibited 2> /dev/null; iptables-save > /etc/iptables/rules.v4;'",
#     ]
#   }
# }