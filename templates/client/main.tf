# Platform of __CLIENT__ on OVH Public Cloud: Managed Kubernetes on the client's
# vRack, Argo CD deploying the apps of this repository (apps/).
terraform {
  required_version = ">= 1.10"

  # State in an Object Storage bucket of the client's project (backend.hcl).
  backend "s3" {}

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

# Credentials: the client's service account, OVH_CLIENT_ID / OVH_CLIENT_SECRET (env.sh).
provider "ovh" {}

provider "helm" {
  kubernetes = {
    host                   = module.platform.kubeconfig_attributes.host
    client_certificate     = base64decode(module.platform.kubeconfig_attributes.client_certificate)
    client_key             = base64decode(module.platform.kubeconfig_attributes.client_key)
    cluster_ca_certificate = base64decode(module.platform.kubeconfig_attributes.cluster_ca_certificate)
  }
}

module "platform" {
  # Pinned release of the module: upgrade on purpose, never by surprise.
  source = "git::https://github.com/antoinepryy/akairos.git//modules/k8s-stack?ref=__MODULE_REF__"

  service_name        = var.service_name
  region              = var.region
  prefix              = var.prefix
  admin_cidr          = var.admin_cidr
  cluster_plan        = var.cluster_plan
  kube_version        = var.kube_version
  private_nodes       = var.private_nodes
  node_flavor         = var.node_flavor
  node_count          = var.node_count
  subnet_cidr         = var.subnet_cidr
  vlan_id             = var.vlan_id
  git_repo_url        = var.git_repo_url
  git_revision        = var.git_revision
  git_ssh_private_key = var.git_ssh_private_key
  app_path            = var.app_path
  app_name            = var.app_name
  app_namespace       = var.app_namespace
}
