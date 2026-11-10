# The floating IP is a Terraform resource of its own: `destroy` deletes it.
resource "ovh_cloud_floating_ip" "lb" {
  service_name = var.service_name
  region       = var.region
  description  = "${var.prefix}-lb-fip"
  depends_on   = [ovh_cloud_gateway.this]
}

# The load balancer itself comes from the legacy resource, used ONLY for what
# the v2 one cannot do: attach the public floating IP (v2 ovh_cloud_loadbalancer
# is refused with "IAM loadbalancer/usePublicIP ... missing
# X-Ovh-Authentication-Detail-Id", 2026-11-10). It declares no listener: the
# listener, pool and members below are separate v2 resources on the same
# Octavia load balancer, so changing instance_count only adds/removes members.
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
}

# The v2 API only sees a load balancer created through v1 some time after v1
# reports it ready: creating the pool right away failed with 404
# "loadbalancer not found" (SBG5, 2026-11-10).
resource "time_sleep" "lb_visible_in_v2" {
  create_duration = "60s"
  triggers        = { lb_id = ovh_cloud_project_loadbalancer.this.id }
}

resource "ovh_cloud_loadbalancer_pool" "http" {
  service_name    = var.service_name
  loadbalancer_id = time_sleep.lb_visible_in_v2.triggers["lb_id"]
  name            = "${var.prefix}-pool"
  protocol        = "HTTP"
  algorithm       = "ROUND_ROBIN"

  # An instance still booting (cloud-init) fails /health and gets no traffic.
  health_monitor = {
    name             = "${var.prefix}-health"
    type             = "HTTP"
    delay            = 5
    timeout          = 3
    max_retries      = 2
    max_retries_down = 2
    http_method      = "GET"
    url_path         = "/health"
    expected_codes   = "200"
  }
}

resource "ovh_cloud_loadbalancer_listener" "http" {
  service_name    = var.service_name
  loadbalancer_id = ovh_cloud_project_loadbalancer.this.id
  name            = "${var.prefix}-http"
  protocol        = "HTTP"
  protocol_port   = 80
  default_pool_id = ovh_cloud_loadbalancer_pool.http.id
}

# One member per instance: scaling adds/removes members, the LB stays.
resource "ovh_cloud_loadbalancer_pool_member" "app" {
  count = var.instance_count

  service_name    = var.service_name
  loadbalancer_id = ovh_cloud_project_loadbalancer.this.id
  pool_id         = ovh_cloud_loadbalancer_pool.http.id
  name            = local.app_names[count.index]
  address         = local.app_ips[count.index]
  protocol_port   = 80
  subnet_id       = ovh_cloud_network_private_vrack_subnet.this.id
}
