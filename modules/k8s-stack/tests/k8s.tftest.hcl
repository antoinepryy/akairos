# Offline tests: mocked providers, nothing is created at OVH.
mock_provider "ovh" {
  mock_resource "ovh_cloud_gateway" {
    defaults = {
      current_state = { external_ip = "198.51.100.30" }
    }
  }
  mock_resource "ovh_cloud_project_kube" {
    defaults = {
      kubeconfig = "apiVersion: v1"
      kubeconfig_attributes = [{
        host                   = "https://example.invalid"
        client_certificate     = "Y2VydA=="
        client_key             = "a2V5"
        cluster_ca_certificate = "Y2E="
      }]
    }
  }
}
mock_provider "helm" {}

variables {
  admin_cidr   = "203.0.113.7/32"
  service_name = "test-project"
  region       = "SBG5"
  prefix       = "akairos"
  git_repo_url = "https://github.com/antoinepryy/akairos.git"
  # The guard would call kubectl on the fake cluster at teardown.
  destroy_guard = false
}

run "cluster" {
  assert {
    condition     = ovh_cloud_project_kube.this.plan == "free"
    error_message = "free plan: no control plane cost"
  }
  assert {
    condition     = ovh_cloud_project_kube.this.private_network_id == ovh_cloud_network_private_vrack.this.id
    error_message = "cluster on the vRack private network"
  }
  assert {
    condition     = ovh_cloud_project_kube.this.load_balancers_subnet_id == ovh_cloud_network_private_vrack_subnet.this.id
    error_message = "Kubernetes load balancers in the private subnet"
  }
  assert {
    condition     = one(ovh_cloud_project_kube.this.private_network_configuration).default_vrack_gateway == "10.43.0.1"
    error_message = "node egress through the gateway"
  }
}

run "network_distinct_from_level1" {
  command = plan
  assert {
    condition     = ovh_cloud_network_private_vrack.this.vlan_id == 43 && ovh_cloud_network_private_vrack_subnet.this.cidr == "10.43.0.0/24"
    error_message = "VLAN 43 / 10.43.0.0/24, level 1 keeps 42 / 10.42.0.0/24"
  }
  assert {
    condition     = ovh_cloud_network_private_vrack.this.name == "akairos-k8s-net"
    error_message = "prefixed name, found by check-leftovers"
  }
}

run "workers" {
  command = plan
  assert {
    condition     = ovh_cloud_project_kube_nodepool.workers.anti_affinity && ovh_cloud_project_kube_nodepool.workers.desired_nodes == 2
    error_message = "two nodes on distinct hosts by default"
  }
  assert {
    condition     = ovh_cloud_project_kube_nodepool.workers.flavor_name == "d2-4"
    error_message = "smallest flavor Managed Kubernetes accepts"
  }
}

run "api_restricted" {
  assert {
    condition     = ovh_cloud_project_kube_iprestrictions.api.ips == toset(["203.0.113.7/32", "198.51.100.30/32"])
    error_message = "API open to the admin and the cluster's own gateway only"
  }
}

run "argocd_application" {
  command = plan
  assert {
    condition     = yamldecode(helm_release.apps.values[0]).applications.web.source.repoURL == "https://github.com/antoinepryy/akairos.git"
    error_message = "Application follows the public repo"
  }
  assert {
    condition     = yamldecode(helm_release.apps.values[0]).applications.web.source.path == "apps/web"
    error_message = "Application deploys the web chart"
  }
  assert {
    condition     = contains(yamldecode(helm_release.apps.values[0]).applications.web.finalizers, "resources-finalizer.argocd.argoproj.io")
    error_message = "deleting the Application deletes the Service and its load balancer"
  }
  assert {
    condition     = yamldecode(helm_release.apps.values[0]).applications.web.syncPolicy.automated.selfHeal
    error_message = "git stays the source of truth"
  }
}

run "trainee_fork" {
  command = plan
  variables { git_repo_url = "https://github.com/trainee/akairos.git" }
  assert {
    condition     = yamldecode(helm_release.apps.values[0]).applications.web.source.repoURL == "https://github.com/trainee/akairos.git"
    error_message = "a fork can be deployed"
  }
}

run "one_node_refused" {
  command = plan
  variables { node_count = 1 }
  expect_failures = [var.node_count]
}

run "admin_cidr_without_mask" {
  command = plan
  variables { admin_cidr = "203.0.113.7" }
  expect_failures = [var.admin_cidr]
}

run "destroy_guard_on_by_default" {
  command = plan
  variables { destroy_guard = true }
  assert {
    condition     = terraform_data.wait_app_gone.input.enabled
    error_message = "the load balancer guard runs on a real destroy"
  }
}

run "standard_private_nodes" {
  command = plan
  variables {
    cluster_plan  = "standard"
    private_nodes = true
  }
  assert {
    condition     = ovh_cloud_project_kube.this.plan == "standard" && ovh_cloud_project_kube.this.disable_public_networking
    error_message = "production profile: standard plan, nodes without public interface"
  }
}

run "private_nodes_need_standard" {
  command = plan
  variables { private_nodes = true }
  expect_failures = [var.private_nodes]
}

run "private_repo_deploy_key" {
  command = plan
  variables {
    git_repo_url        = "git@github.com:client/platform.git"
    git_ssh_private_key = "-----BEGIN OPENSSH PRIVATE KEY-----\nfake\n-----END OPENSSH PRIVATE KEY-----\n"
  }
  assert {
    condition     = length(helm_release.argocd.values) == 2
    error_message = "repository credentials passed to Argo CD"
  }
  assert {
    condition     = yamldecode(helm_release.argocd.values[1]).configs.repositories.app.url == "git@github.com:client/platform.git"
    error_message = "credentials bound to the application repository"
  }
}

run "public_repo_no_credentials" {
  command = plan
  assert {
    condition     = length(helm_release.argocd.values) == 1
    error_message = "no repository secret for a public repository"
  }
}

run "custom_app_namespace" {
  command = plan
  variables {
    app_name      = "shop"
    app_namespace = "shop"
  }
  assert {
    condition     = yamldecode(helm_release.apps.values[0]).applications.shop.destination.namespace == "shop"
    error_message = "Application name and namespace configurable"
  }
  assert {
    condition     = terraform_data.wait_app_gone.input.namespace == "shop"
    error_message = "destroy guard watches the app namespace"
  }
}

run "bad_prefix" {
  command = plan
  variables { prefix = "Client_ACME" }
  expect_failures = [var.prefix]
}
