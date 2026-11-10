output "kubeconfig" {
  value     = module.platform.kubeconfig
  sensitive = true
}

output "cluster_id" {
  value = module.platform.cluster_id
}

output "gateway_ip" {
  description = "Public IP the platform's outbound traffic leaves from (to allow on the client's side if needed)."
  value       = module.platform.gateway_ip
}
