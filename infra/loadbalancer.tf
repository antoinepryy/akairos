# The floating IP is a Terraform resource of its own: `destroy` deletes it,
# and it survives a load balancer replacement (same demo URL).
resource "ovh_cloud_floating_ip" "lb" {
  service_name = var.service_name
  region       = var.region
  description  = "${var.prefix}-lb-fip"
  depends_on   = [ovh_cloud_gateway.this]
}

# Legacy resource on purpose: with the v2 ovh_cloud_loadbalancer, attaching a
# public IP requires the IAM action loadbalancer/usePublicIP, which OVH refuses
# for API keys AND service accounts ("missing X-Ovh-Authentication-Detail-Id",
# 2026-11-10). Trade-off: members are inline and force replacement, so changing
# instance_count recreates the LB (a few minutes of downtime, same IP).
resource "ovh_cloud_project_loadbalancer" "this" {
  service_name = var.service_name
  region_name  = var.region
  name         = "${var.prefix}-lb"
  flavor_id    = local.lb_flavor_id

  network = {
    private = {
      network = {
        id        = ovh_cloud_network_private_vrack.this.id
        subnet_id = ovh_cloud_network_private_vrack_subnet.this.id
      }
      gateway = {
        id = ovh_cloud_gateway.this.id
      }
      floating_ip = {
        id = ovh_cloud_floating_ip.lb.current_state.id
      }
    }
  }

  listeners = [{
    name     = "${var.prefix}-http"
    port     = 80
    protocol = "http"

    pool = {
      name      = "${var.prefix}-pool"
      protocol  = "http"
      algorithm = "roundRobin"

      # An instance still booting (cloud-init) fails /health and gets no traffic.
      health_monitor = {
        name             = "${var.prefix}-health"
        monitor_type     = "http"
        delay            = 5
        timeout          = 3
        max_retries      = 2
        max_retries_down = 2
        http_configuration = {
          http_method    = "GET"
          url_path       = "/health"
          expected_codes = "200"
        }
      }

      members = [for i, ip in local.app_ips : {
        name          = local.app_names[i]
        address       = ip
        protocol_port = 80
      }]
    }
  }]
}
