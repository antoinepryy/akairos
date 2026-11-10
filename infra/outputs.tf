output "lb_url" {
  description = "Demo URL."
  value       = "http://${ovh_cloud_floating_ip.lb.current_state.ip}"
}

output "bastion_ip" {
  description = "Public IPv4 (floating) of the bastion."
  value       = ovh_cloud_floating_ip.bastion.current_state.ip
}

output "app_private_ips" {
  value = local.app_ips
}

output "ssh_config" {
  description = "Paste into ~/.ssh/config."
  value       = <<-EOT
    Host ${var.prefix}-bastion
      HostName ${ovh_cloud_floating_ip.bastion.current_state.ip}
      User debian
    %{for i, ip in local.app_ips~}
    Host ${local.app_names[i]}
      HostName ${coalesce(ip, "unknown")}
      User debian
      ProxyJump ${var.prefix}-bastion
    %{endfor~}
  EOT
}

output "lb_id" {
  description = "Load balancer id (used by tests to detect replacement)."
  value       = ovh_cloud_project_loadbalancer.this.id
}
