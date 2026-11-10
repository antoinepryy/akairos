# The project is already attached to vRack pn-1380461; it is a prerequisite
# kept outside Terraform. Only the network, subnet and gateway live here.
resource "ovh_cloud_network_private_vrack" "this" {
  service_name = var.service_name
  region       = var.region
  name         = "${var.prefix}-net"
  vlan_id      = var.vlan_id
}

resource "ovh_cloud_network_private_vrack_subnet" "this" {
  service_name    = var.service_name
  region          = var.region
  network_id      = ovh_cloud_network_private_vrack.this.id
  name            = "${var.prefix}-subnet"
  cidr            = var.subnet_cidr
  gateway_ip      = cidrhost(var.subnet_cidr, 1)
  dhcp_enabled    = true
  dns_nameservers = ["213.186.33.99"]

  # Fixed IPs (.5 bastion, .10+ apps) stay outside the DHCP pool.
  allocation_pools = [{
    start = cidrhost(var.subnet_cidr, 100)
    end   = cidrhost(var.subnet_cidr, 200)
  }]
}

# Router with SNAT: outbound Internet for the private instances (apt), and
# carrier of the load balancer floating IP.
resource "ovh_cloud_gateway" "this" {
  service_name = var.service_name
  region       = var.region
  name         = "${var.prefix}-gw"
  subnet_ids   = [ovh_cloud_network_private_vrack_subnet.this.id]

  external_gateway = {
    enabled = true
    model   = "S"
  }
}
