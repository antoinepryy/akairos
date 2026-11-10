output "kubeconfig" {
  description = "terraform -chdir=k8s output -raw kubeconfig > k8s/kubeconfig.yml (or scripts/k8s-kubeconfig.sh)"
  value       = ovh_cloud_project_kube.this.kubeconfig
  sensitive   = true
}

output "cluster_id" {
  value = ovh_cloud_project_kube.this.id
}

output "gateway_ip" {
  description = "Public IP the cluster's outbound traffic leaves from."
  value       = ovh_cloud_gateway.this.current_state.external_ip
}

output "argocd_app" {
  value = "${var.git_repo_url} @ ${var.git_revision}, path ${var.app_path}"
}
