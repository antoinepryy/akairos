# Separate floating IP, listener, pool and members: scaling instance_count only
# adds/removes members, the load balancer and its public IP stay in place, and
# `destroy` deletes the floating IP explicitly.
resource "ovh_cloud_floating_ip" "lb" {
  service_name = var.service_name
  region       = var.region
  description  = "${var.prefix}-lb-fip"
  depends_on   = [ovh_cloud_gateway.this]
}

resource "ovh_cloud_loadbalancer" "this" {
  service_name = var.service_name
  region       = var.region
  name         = "${var.prefix}-lb"
  flavor_name  = "SMALL"

  network = {
    id        = ovh_cloud_network_private_vrack.this.id
    subnet_id = ovh_cloud_network_private_vrack_subnet.this.id
    # Outside the subnet CIDR: associates this existing floating IP to the VIP.
    ip = ovh_cloud_floating_ip.lb.current_state.ip
  }
}

resource "ovh_cloud_loadbalancer_pool" "http" {
  service_name    = var.service_name
  loadbalancer_id = ovh_cloud_loadbalancer.this.id
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
  loadbalancer_id = ovh_cloud_loadbalancer.this.id
  name            = "${var.prefix}-http"
  protocol        = "HTTP"
  protocol_port   = 80
  default_pool_id = ovh_cloud_loadbalancer_pool.http.id
}

# Same range as the instances: scaling down removes the matching member.
resource "ovh_cloud_loadbalancer_pool_member" "app" {
  count = var.instance_count

  service_name    = var.service_name
  loadbalancer_id = ovh_cloud_loadbalancer.this.id
  pool_id         = ovh_cloud_loadbalancer_pool.http.id
  name            = local.app_names[count.index]
  address         = local.app_ips[count.index]
  protocol_port   = 80
  subnet_id       = ovh_cloud_network_private_vrack_subnet.this.id

  depends_on = [ovh_cloud_instance.app]
}
