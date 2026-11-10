locals {
  allow_all_egress = [
    { direction = "egress", ethernet_type = "IPv4", description = "all outbound IPv4" },
    { direction = "egress", ethernet_type = "IPv6", description = "all outbound IPv6" },
  ]
}

# Bastion: SSH from the admin only.
resource "ovh_cloud_security_group" "bastion" {
  service_name = var.service_name
  region       = var.region
  name         = "${var.prefix}-bastion-sg"
  description  = "SSH from admin_cidr only"

  rule = concat(local.allow_all_egress, [{
    direction        = "ingress"
    ethernet_type    = "IPv4"
    protocol         = "tcp"
    port_range_min   = 22
    port_range_max   = 22
    remote_ip_prefix = var.admin_cidr
    description      = "SSH from admin"
  }])
}

# App instances: HTTP from the private subnet (load balancer), SSH from the bastion only.
resource "ovh_cloud_security_group" "app" {
  service_name = var.service_name
  region       = var.region
  name         = "${var.prefix}-app-sg"
  description  = "HTTP from the subnet, SSH from the bastion"

  rule = concat(local.allow_all_egress, [
    {
      direction        = "ingress"
      ethernet_type    = "IPv4"
      protocol         = "tcp"
      port_range_min   = 80
      port_range_max   = 80
      remote_ip_prefix = var.subnet_cidr
      description      = "HTTP from load balancer subnet"
    },
    {
      direction       = "ingress"
      ethernet_type   = "IPv4"
      protocol        = "tcp"
      port_range_min  = 22
      port_range_max  = 22
      remote_group_id = ovh_cloud_security_group.bastion.id
      description     = "SSH from bastion"
    },
  ])
}
