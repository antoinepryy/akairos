# The docker-swarm Bedrock demo on Managed Kubernetes: the k8s-stack module
# (cluster, Argo CD, the app's restricted project) plus what the app needs on
# the cluster, installed here because a commit in the app's repository may not
# install cluster-wide things: Traefik (ingress, the only load balancer),
# cert-manager (Let's Encrypt) and mariadb-operator (Galera).
# Argo CD then keeps apps/bedrock in sync with git.

locals {
  # Not a variable: env.sh exports TF_VAR_prefix=akairos for level 2, and the
  # two clusters must not share names (network, nodes, check-leftovers).
  prefix = "bedrock"

  # The module's default kinds, plus the custom resources of the chart.
  app_resource_kinds = [
    { group = "", kind = "ConfigMap" },
    { group = "", kind = "Secret" },
    { group = "", kind = "Service" },
    { group = "", kind = "ServiceAccount" },
    { group = "", kind = "PersistentVolumeClaim" },
    { group = "apps", kind = "Deployment" },
    { group = "apps", kind = "StatefulSet" },
    { group = "batch", kind = "Job" },
    { group = "batch", kind = "CronJob" },
    { group = "policy", kind = "PodDisruptionBudget" },
    { group = "autoscaling", kind = "HorizontalPodAutoscaler" },
    { group = "networking.k8s.io", kind = "NetworkPolicy" },
    { group = "networking.k8s.io", kind = "Ingress" },
    { group = "cert-manager.io", kind = "Issuer" },
    { group = "k8s.mariadb.com", kind = "MariaDB" },
    { group = "k8s.mariadb.com", kind = "Database" },
    { group = "k8s.mariadb.com", kind = "User" },
    { group = "k8s.mariadb.com", kind = "Grant" },
  ]
}

module "k8s" {
  source = "../modules/k8s-stack"

  service_name = var.service_name
  region       = var.region
  prefix       = local.prefix
  admin_cidr   = var.admin_cidr
  node_count   = var.node_count
  node_flavor  = var.node_flavor
  # Level 1 uses VLAN 42, level 2 VLAN 43.
  vlan_id     = 44
  subnet_cidr = "10.44.0.0/24"

  git_repo_url       = var.git_repo_url
  git_revision       = var.git_revision
  app_name           = "bedrock"
  app_namespace      = "bedrock"
  app_path           = "apps/bedrock"
  app_resource_kinds = local.app_resource_kinds
  destroy_guard      = var.destroy_guard

  # The Application comes after these releases and is deleted before them:
  # mariadb-operator must still run to remove the Galera cluster and its
  # volumes, Traefik's load balancer is watched by its own guard below.
  platform_ready = [
    helm_release.traefik.id,
    helm_release.cert_manager.id,
    helm_release.mariadb_operator.id,
  ]
}

# Nodes up and API restricted to the admin IP: the releases below can install.
resource "terraform_data" "api_ready" {
  input = module.k8s.api_ready
}

# Destroy-time guard for Traefik's load balancer, created by Kubernetes, not
# by Terraform (same script as the app's guard in the module). Created before
# Traefik, so destroyed after it: it waits until OVH has deleted the load
# balancer, and only then the cluster goes.
resource "terraform_data" "traefik_lb_gone" {
  input = {
    kubeconfig = module.k8s.kubeconfig
    script     = file("${path.module}/../modules/k8s-stack/scripts/wait-app-gone.sh")
    enabled    = var.destroy_guard
  }

  provisioner "local-exec" {
    when = destroy
    environment = {
      KUBECONFIG_CONTENT = self.input.kubeconfig
      GUARD_ENABLED      = tostring(self.input.enabled)
      APP_NAME           = ""
      APP_NAMESPACE      = "traefik"
    }
    interpreter = ["bash", "-c"]
    command     = self.input.script
  }

  depends_on = [terraform_data.api_ready]
}

# The only public entry point: one OVH load balancer in front of two Traefik
# pods on different nodes (on Swarm, Traefik ran on swarm-1 only).
resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.traefik_chart_version
  timeout          = 900

  values = [yamlencode({
    deployment          = { replicas = 2 }
    podDisruptionBudget = { enabled = true, maxUnavailable = 1 }
    topologySpreadConstraints = [{
      maxSkew           = 1
      topologyKey       = "kubernetes.io/hostname"
      whenUnsatisfiable = "DoNotSchedule"
      labelSelector     = { matchLabels = { "app.kubernetes.io/name" = "traefik" } }
    }]
    service = {
      # Kubernetes asks OVH for an Octavia load balancer with a floating IP.
      annotations = { "loadbalancer.ovhcloud.com/flavor" = "small" }
    }
    accessLog = { enabled = true }
  })]

  depends_on = [terraform_data.traefik_lb_gone]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.cert_manager_chart_version
  timeout          = 900

  values = [yamlencode({
    # keep: uninstalling cert-manager would otherwise delete every Issuer and
    # Certificate of the cluster with the CRDs. The cluster goes anyway here.
    crds = { enabled = true, keep = true }
  })]

  depends_on = [terraform_data.api_ready]
}

# CRDs in their own release, as the operator's chart recommends: upgrading
# the operator never removes them (and with them every MariaDB).
resource "helm_release" "mariadb_operator_crds" {
  name             = "mariadb-operator-crds"
  namespace        = "mariadb-operator"
  create_namespace = true
  repository       = "https://helm.mariadb.com/mariadb-operator"
  chart            = "mariadb-operator-crds"
  version          = var.mariadb_operator_chart_version

  depends_on = [terraform_data.api_ready]
}

resource "helm_release" "mariadb_operator" {
  name       = "mariadb-operator"
  namespace  = "mariadb-operator"
  repository = "https://helm.mariadb.com/mariadb-operator"
  chart      = "mariadb-operator"
  version    = var.mariadb_operator_chart_version
  timeout    = 900

  depends_on = [helm_release.mariadb_operator_crds]
}
