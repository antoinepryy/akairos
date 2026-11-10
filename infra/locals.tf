locals {
  app_names = [for i in range(var.instance_count) : "${var.prefix}-app-${i + 1}"]

  # Private IPv4 picked by OVH IPAM (fixed IPs must sit inside the DHCP pool,
  # so we let the platform choose and read them back after creation).
  app_ips = [for i in ovh_cloud_instance.app : try(one([
    for a in flatten([for n in i.current_state.networks : n.addresses]) : a.ip
    if a.version == 4 && a.type == "FIXED"
  ]), null)]

  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}
