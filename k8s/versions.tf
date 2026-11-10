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

# Talks to the cluster created below. Only helm_release is used (no
# kubernetes_manifest): it does not need the API server at plan time, so the
# cluster and what runs on it can be created in a single apply.
provider "helm" {
  kubernetes = {
    host                   = local.kube.host
    client_certificate     = base64decode(local.kube.client_certificate)
    client_key             = base64decode(local.kube.client_key)
    cluster_ca_certificate = base64decode(local.kube.cluster_ca_certificate)
  }
}
