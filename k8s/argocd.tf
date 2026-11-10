resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  timeout          = 900

  values = [yamlencode({
    dex           = { enabled = false }
    notifications = { enabled = false }
    configs = {
      # Poll git every 30 s instead of 3 min: a push shows up quickly in the demo.
      cm     = { "timeout.reconciliation" = "30s", "timeout.reconciliation.jitter" = "0s" }
      params = { "server.insecure" = true }
    }
  })]

  depends_on = [
    ovh_cloud_project_kube_nodepool.workers,
    ovh_cloud_project_kube_iprestrictions.api,
  ]
}

# Destroy-time guard. The load balancer of the app is created by Kubernetes,
# not by Terraform: if the cluster went away first, it would stay (and stay
# billed) at OVH. On destroy, Terraform removes the Application first, then
# this resource waits until its Service is gone (a Service of type
# LoadBalancer only disappears once OVH has deleted the load balancer), and
# only then removes Argo CD and the cluster.
resource "terraform_data" "wait_app_gone" {
  input = {
    kubeconfig = ovh_cloud_project_kube.this.kubeconfig
    script     = abspath("${path.module}/../scripts/k8s-wait-app-gone.sh")
    enabled    = var.destroy_guard
  }

  provisioner "local-exec" {
    when = destroy
    environment = {
      KUBECONFIG_CONTENT = self.input.kubeconfig
      GUARD_ENABLED      = tostring(self.input.enabled)
    }
    command = self.input.script
  }

  depends_on = [helm_release.argocd]
}

# The Application: Argo CD keeps namespace "web" in sync with the chart in git.
resource "helm_release" "apps" {
  name       = "argocd-apps"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [yamlencode({
    applications = {
      web = {
        namespace = "argocd"
        # Deleting the Application deletes what it deployed (Service and LB included).
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        project    = "default"
        source = {
          repoURL        = var.git_repo_url
          targetRevision = var.git_revision
          path           = var.app_path
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = "web"
        }
        syncPolicy = {
          # selfHeal: a manual "kubectl scale" is reverted, git stays the truth.
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
        }
      }
    }
  })]

  depends_on = [terraform_data.wait_app_gone]
}
