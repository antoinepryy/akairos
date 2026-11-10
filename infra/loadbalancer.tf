# Legacy resource on purpose: the new ovh_cloud_loadbalancer cannot attach a
# floating IP yet (provider 2.24), and the demo needs a public entry point.
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
      floating_ip_create = {
        description = "${var.prefix}-lb-fip"
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

      # Derived from the same range as the instances: scaling down removes members.
      members = [for i, ip in local.app_ips : {
        name          = local.app_names[i]
        address       = ip
        protocol_port = 80
      }]
    }
  }]

  depends_on = [ovh_cloud_instance.app]
}
