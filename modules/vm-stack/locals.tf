locals {
  app_names = [for i in range(var.instance_count) : "${var.prefix}-app-${i + 1}"]

  # Private IPv4 picked by OVH IPAM (fixed IPs must sit inside the DHCP pool,
  # so we let the platform choose and read them back after creation).
  app_fixed_ips = [for i in ovh_cloud_instance.app : [
    for a in flatten([for n in try(i.current_state.networks, []) : n.addresses]) : a.ip
    if a.version == 4 && a.type == "FIXED"
  ]]
  # "" only happens under mocked tests: a real instance always has one.
  app_ips = [for ips in local.app_fixed_ips : length(ips) > 0 ? ips[0] : ""]

  ssh_public_key = trimspace(var.ssh_public_key)
}
