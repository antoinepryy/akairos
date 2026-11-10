locals {
  gateway_ip = cidrhost(var.subnet_cidr, 1)
}

# Free plan: the control plane costs nothing, only nodes and load balancers are
# billed. Standard (0.09 EUR/h on 2026-11-10): SLA, and nodes without public IP.
resource "ovh_cloud_project_kube" "this" {
  service_name = var.service_name
  region       = var.region
  name         = "${var.prefix}-k8s"
  plan         = var.cluster_plan
  version      = var.kube_version

  # Nodes get no public interface at all (Standard plan only, creation only).
  disable_public_networking = var.private_nodes ? true : null
  private_network_id        = ovh_cloud_network_private_vrack.this.id
  nodes_subnet_id           = ovh_cloud_network_private_vrack_subnet.this.id

  # Load balancers created by "Service type: LoadBalancer" land in this subnet.
  load_balancers_subnet_id = ovh_cloud_network_private_vrack_subnet.this.id

  private_network_configuration {
    # All node egress leaves through the gateway, so the API server sees a
    # single, known source IP (allowed in the IP restrictions below).
    default_vrack_gateway              = local.gateway_ip
    private_network_routing_as_default = true
  }

  depends_on = [ovh_cloud_gateway.this]
}

resource "ovh_cloud_project_kube_nodepool" "workers" {
  service_name  = var.service_name
  kube_id       = ovh_cloud_project_kube.this.id
  name          = "${var.prefix}-k8s-workers"
  flavor_name   = var.node_flavor
  desired_nodes = var.node_count
  min_nodes     = 2
  max_nodes     = 5
  autoscale     = false

  # Every node on a different physical host: losing one host loses one node.
  anti_affinity = true
}

# Same role as the bastion of level 1: the API answers the admin IP only.
# The gateway IP is the in-cluster traffic (Argo CD) leaving through the vRack.
resource "ovh_cloud_project_kube_iprestrictions" "api" {
  service_name = var.service_name
  kube_id      = ovh_cloud_project_kube.this.id
  ips          = [var.admin_cidr, "${ovh_cloud_gateway.this.current_state.external_ip}/32"]

  # OVH refuses the update while a node pool is INSTALLING (400 IntegrityError).
  depends_on = [ovh_cloud_project_kube_nodepool.workers]
}
