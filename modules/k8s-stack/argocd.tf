locals {
  argocd_base_values = yamlencode({
    dex           = { enabled = false }
    notifications = { enabled = false }
    configs = {
      # Poll git every 30 s instead of 3 min: a push shows up quickly.
      cm = { "timeout.reconciliation" = "30s", "timeout.reconciliation.jitter" = "0s" }
      # Plain HTTP inside the cluster: the UI is only reached through
      # "kubectl port-forward" (localhost), never exposed (see network policies).
      params = { "server.insecure" = true }
    }
    # The chart's own policy for argocd-server allows any source (ingress: [{}]),
    # and a per-component switch cannot turn it off while the global one is on.
    # So: global off, the chart's restrictive policies on, argocd-server's
    # replaced by ours (extraObjects), plus a default deny for the namespace.
    global         = { networkPolicy = { create = false } }
    controller     = { networkPolicy = { create = true } }
    repoServer     = { networkPolicy = { create = true } }
    redis          = { networkPolicy = { create = true } }
    applicationSet = { networkPolicy = { create = true } }
    server         = { networkPolicy = { create = false } }
    extraObjects = [
      {
        apiVersion = "networking.k8s.io/v1"
        kind       = "NetworkPolicy"
        metadata   = { name = "default-deny-ingress" }
        spec       = { podSelector = {}, policyTypes = ["Ingress"] }
      },
      {
        # API and UI of Argo CD: only from pods of the argocd namespace. An
        # app pod, compromised or not, cannot reach it. port-forward goes
        # through the kubelet and is not subject to network policies.
        apiVersion = "networking.k8s.io/v1"
        kind       = "NetworkPolicy"
        metadata   = { name = "argocd-server-same-namespace" }
        spec = {
          podSelector = { matchLabels = { "app.kubernetes.io/name" = "argocd-server" } }
          policyTypes = ["Ingress"]
          ingress     = [{ from = [{ podSelector = {} }] }]
        }
      },
    ]
  })

  # Private repository: Argo CD reads it with a read-only deploy key.
  argocd_repo_values = var.git_ssh_private_key == null ? [] : [yamlencode({
    configs = {
      repositories = {
        app = { url = var.git_repo_url, type = "git", sshPrivateKey = var.git_ssh_private_key }
      }
    }
  })]

  argocd_values = concat([local.argocd_base_values], local.argocd_repo_values)

  project_values = yamlencode({
    projects = {
      (var.app_name) = {
        namespace   = "argocd"
        description = "App ${var.app_name}: one repository, one namespace"
        sourceRepos = [var.git_repo_url]
        destinations = [{
          server    = "https://kubernetes.default.svc"
          namespace = var.app_namespace
        }]
        clusterResourceWhitelist   = [{ group = "", kind = "Namespace" }]
        namespaceResourceWhitelist = var.app_resource_kinds
      }
    }
  })

  apps_values = yamlencode({
    applications = {
      (var.app_name) = {
        namespace = "argocd"
        # Deleting the Application deletes what it deployed (Service and LB included).
        finalizers = ["resources-finalizer.argocd.argoproj.io"]
        project    = var.app_name
        source = {
          repoURL        = var.git_repo_url
          targetRevision = var.git_revision
          path           = var.app_path
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.app_namespace
        }
        syncPolicy = {
          # selfHeal: a manual "kubectl scale" is reverted, git stays the truth.
          automated   = { prune = true, selfHeal = true }
          syncOptions = ["CreateNamespace=true"]
          # Pod Security "restricted" on the app's namespace: a pod running as
          # root, privileged or with extra capabilities is refused.
          managedNamespaceMetadata = {
            labels = {
              "pod-security.kubernetes.io/enforce" = "restricted"
              "pod-security.kubernetes.io/warn"    = "restricted"
            }
          }
        }
      }
    }
  })
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  timeout          = 900

  values = local.argocd_values

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
    # The script's content, not its path: the destroy may run from another
    # machine or checkout than the apply that wrote the state.
    script    = file("${path.module}/scripts/wait-app-gone.sh")
    enabled   = var.destroy_guard
    namespace = var.app_namespace
    app       = var.app_name
  }

  provisioner "local-exec" {
    when = destroy
    environment = {
      KUBECONFIG_CONTENT = self.input.kubeconfig
      GUARD_ENABLED      = tostring(self.input.enabled)
      APP_NAMESPACE      = self.input.namespace
      APP_NAME           = self.input.app
    }
    interpreter = ["bash", "-c"]
    command     = self.input.script
  }

  depends_on = [helm_release.project]
}

# The Argo CD project of the app, instead of "default" (which may deploy
# anything anywhere): only this repository, only var.app_namespace, only the
# namespaced kinds of var.app_resource_kinds (no Role or RoleBinding), and no
# cluster-scoped resource but the namespace itself (CreateNamespace). A commit
# in the app's repository cannot grant itself rights on the cluster.
# Own release, created before and destroyed after the Application: Argo CD
# needs the project to process the Application's deletion.
resource "helm_release" "project" {
  name       = "argocd-project"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [local.project_values]

  depends_on = [helm_release.argocd]
}

# The Application: Argo CD keeps var.app_namespace in sync with the chart in git.
resource "helm_release" "apps" {
  name       = "argocd-apps"
  namespace  = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version

  values = [local.apps_values]

  depends_on = [terraform_data.wait_app_gone]
}
