output "kubeconfig" {
  description = "Admin kubeconfig of the cluster (write it to a chmod 600 file)."
  value       = ovh_cloud_project_kube.this.kubeconfig
  sensitive   = true
}

output "kubeconfig_attributes" {
  description = "host and base64 certificates, for the helm provider of the calling configuration."
  value       = ovh_cloud_project_kube.this.kubeconfig_attributes[0]
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

output "api_ready" {
  description = "Known once the nodes are up and the API restricted: what the caller installs on the cluster depends on it."
  value       = ovh_cloud_project_kube_iprestrictions.api.id
}
