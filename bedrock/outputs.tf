output "kubeconfig" {
  description = "scripts/k8s-kubeconfig.sh bedrock writes it to bedrock/kubeconfig.yml."
  value       = module.k8s.kubeconfig
  sensitive   = true
}

output "cluster_id" {
  value = module.k8s.cluster_id
}

output "gateway_ip" {
  value = module.k8s.gateway_ip
}

output "argocd_app" {
  value = module.k8s.argocd_app
}
