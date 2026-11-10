locals {
  # Fixed private IPs for the app instances, outside the DHCP pool (.100-.200),
  # so the load balancer members and the SSH config are known at plan time.
  app_ips   = [for i in range(var.instance_count) : cidrhost(var.subnet_cidr, 10 + i)]
  app_names = [for i in range(var.instance_count) : "${var.prefix}-app-${i + 1}"]

  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}
