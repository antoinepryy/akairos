# Same vRack as level 1 (attached to the project outside Terraform), but its
# own VLAN and subnet: both levels can run side by side.
resource "ovh_cloud_network_private_vrack" "this" {
  service_name = var.service_name
  region       = var.region
  name         = "${var.prefix}-k8s-net"
  vlan_id      = var.vlan_id
}

resource "ovh_cloud_network_private_vrack_subnet" "this" {
  service_name    = var.service_name
  region          = var.region
  network_id      = ovh_cloud_network_private_vrack.this.id
  name            = "${var.prefix}-k8s-subnet"
  cidr            = var.subnet_cidr
  gateway_ip      = local.gateway_ip
  dhcp_enabled    = true
  dns_nameservers = ["213.186.33.99"]

  allocation_pools = [{
    start = cidrhost(var.subnet_cidr, 10)
    end   = cidrhost(var.subnet_cidr, 250)
  }]
}

# Mandatory for a cluster on a private network: node egress (SNAT) and the
# floating IPs of the load balancers Kubernetes creates.
resource "ovh_cloud_gateway" "this" {
  service_name = var.service_name
  region       = var.region
  name         = "${var.prefix}-k8s-gw"
  subnet_ids   = [ovh_cloud_network_private_vrack_subnet.this.id]

  external_gateway = {
    enabled = true
    model   = "S"
  }
}
