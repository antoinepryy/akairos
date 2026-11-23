terraform {
  required_version = ">= 1.9"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }
}

# Credentials come from the environment (see ../env.sh): OVH_CLIENT_ID / OVH_CLIENT_SECRET.
provider "ovh" {}

# Talks to the cluster the module creates. Only helm_release is used (no
# kubernetes_manifest), so the cluster and what runs on it fit in one apply.
provider "helm" {
  kubernetes = {
    host                   = module.k8s.kubeconfig_attributes.host
    client_certificate     = base64decode(module.k8s.kubeconfig_attributes.client_certificate)
    client_key             = base64decode(module.k8s.kubeconfig_attributes.client_key)
    cluster_ca_certificate = base64decode(module.k8s.kubeconfig_attributes.cluster_ca_certificate)
  }
}
