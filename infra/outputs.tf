output "lb_url" {
  value = module.vm.lb_url
}

output "bastion_ip" {
  value = module.vm.bastion_ip
}

output "app_private_ips" {
  value = module.vm.app_private_ips
}

output "ssh_config" {
  value = module.vm.ssh_config
}
