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
  admin_cidr = "203.0.113.7/32"
  # The guards would call kubectl on the fake cluster at teardown.
  destroy_guard = false
}

run "own_names" {
  command = plan
  assert {
    condition     = local.prefix == "bedrock"
    error_message = "prefix bedrock, distinct from level 2 (akairos): env.sh's TF_VAR_prefix cannot change it"
  }
  assert {
    condition     = var.node_count == 3 && var.node_flavor == "d2-8"
    error_message = "3 x d2-8: one Galera pod per node"
  }
}

run "argocd_follows_the_chart" {
  assert {
    condition     = output.argocd_app == "https://github.com/antoinepryy/akairos.git @ bedrock, path apps/bedrock"
    error_message = "Argo CD deploys apps/bedrock from the public repository"
  }
}

run "project_allows_chart_kinds" {
  command = plan
  assert {
    condition = alltrue([
      for k in ["MariaDB", "Database", "User", "Grant", "Issuer", "Ingress"] :
      contains([for x in local.app_resource_kinds : x.kind], k)
    ])
    error_message = "the Argo CD project accepts every kind of apps/bedrock"
  }
  assert {
    condition     = !contains([for x in local.app_resource_kinds : x.kind], "Role") && !contains([for x in local.app_resource_kinds : x.kind], "RoleBinding")
    error_message = "still no Role nor RoleBinding from git"
  }
}

run "destroy_guards_on_by_default" {
  command = plan
  variables {
    destroy_guard = true
  }
  assert {
    condition     = terraform_data.traefik_lb_gone.input.enabled
    error_message = "Traefik's load balancer is waited for at destroy"
  }
}
