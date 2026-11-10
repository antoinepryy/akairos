output "kubeconfig" {
  description = "scripts/k8s-kubeconfig.sh writes it to k8s/kubeconfig.yml."
  value       = module.k8s.kubeconfig
  sensitive   = true
}

output "cluster_id" {
  value = module.k8s.cluster_id
}

output "gateway_ip" {
  value = module.k8s.gateway_ip
}
