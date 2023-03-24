# Deploys an intermediary device. Configuration is done after the CSP connections are created.
resource "tls_private_key" "ne_intermediary" {
  count = var.edge["intermediary_type"] == "network-edge" ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "equinix_network_ssh_key" "ne_intermediary" {
  count = var.edge["intermediary_type"] == "network-edge" ? 1 : 0

  name       = local.ne_intermediary_name
  public_key = one(tls_private_key.ne_intermediary).public_key_openssh
}

resource "local_sensitive_file" "ne_intermediary" {
  count = var.edge["intermediary_type"] == "network-edge" ? 1 : 0

  content  = one(tls_private_key.ne_intermediary).private_key_openssh
  filename = "./${local.site_id}-ne-intermediary-private-key"
}

resource "equinix_network_device" "ne_intermediary" {
  count = var.edge["intermediary_type"] == "network-edge" ? 1 : 0

  metro_code      = data.equinix_network_account.this.metro_code
  account_number  = data.equinix_network_account.this.number
  type_code       = "C8000V"
  byol            = true
  self_managed    = true
  core_count      = var.edge["core_count"]
  package_code    = "network-essentials"
  version         = "17.06.01a"
  name            = local.ne_intermediary_name
  hostname        = local.ne_intermediary_name
  notifications   = var.edge["notifications"]
  term_length     = var.edge["term_length"]
  acl_template_id = equinix_network_acl_template.this.id

  ssh_key {
    username = "admin"
    key_name = one(equinix_network_ssh_key.ne_intermediary).name
  }
}

resource "local_file" "intermediary_config" {
  count = var.edge["intermediary_type"] != "none" ? 1 : 0

  content = jsonencode({
    interfaces = [for k, v in module.csp_connections : {
      name = "GigabitEthernet${v.edge_interface}",
      ip   = values(v.customer_side_peering_addresses)[0]
    }],
    neighbors = [for k, v in module.csp_connections : {
      asn = v.csp_asn
      ip  = values(v.csp_side_peering_addresses)[0]
    }],
    wan_ip            = "${local.wan_default}/${local.wan_prefixlen}",
    wan_network       = var.edge["wan_interface_ip_prefix"],
    customer_side_asn = var.edge["customer_side_asn"]
  })
  filename = "./config.json"
}

resource "ansible_host" "ne_intermediary" {
  count = var.edge["intermediary_type"] == "network-edge" ? 1 : 0

  name = one(equinix_network_device.ne_intermediary).ssh_ip_fqdn

  variables = {
    ansible_connection    = "ansible.netcommon.network_cli",
    ansible_network_os    = "cisco.ios.ios",
    ansible_user          = "admin",
    ansible_become        = "yes",
    ansible_become_method = "enable",
    #export ANSIBLE_HOST_KEY_CHECKING=False
    ansible_ssh_private_key_file = one(local_sensitive_file.ne_intermediary).filename
  }
}