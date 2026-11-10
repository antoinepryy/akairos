locals {
  bastion_public_ip = try([
    for a in flatten([for n in ovh_cloud_instance.bastion.current_state.networks : n.addresses]) : a.ip
    if a.version == 4 && a.ip != local.bastion_ip
  ][0], "")
}

output "lb_url" {
  description = "Demo URL."
  value       = "http://${try(ovh_cloud_project_loadbalancer.this.floating_ip.ip, "")}"
}

output "bastion_ip" {
  description = "Public IPv4 of the bastion."
  value       = local.bastion_public_ip
}

output "app_private_ips" {
  value = local.app_ips
}

output "ssh_config" {
  description = "Paste into ~/.ssh/config."
  value       = <<-EOT
    Host ${var.prefix}-bastion
      HostName ${local.bastion_public_ip}
      User debian
    %{for i, ip in local.app_ips~}
    Host ${local.app_names[i]}
      HostName ${ip}
      User debian
      ProxyJump ${var.prefix}-bastion
    %{endfor~}
  EOT
}
