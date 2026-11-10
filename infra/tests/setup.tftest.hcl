# Offline tests: mocked provider, nothing is created at OVH.
mock_provider "ovh" {
  mock_resource "ovh_cloud_floating_ip" {
    defaults = {
      id            = "198.51.100.20"
      current_state = { id = "fip-uuid", ip = "198.51.100.20" }
    }
  }
}

# Mocks cannot fake the nested lists of the flavor/image data sources,
# so the lookups are pinned here (the lookup logic itself runs live).
variables {
  admin_cidr          = "203.0.113.7/32"
  ssh_public_key_path = "./tests/fixtures/id_test.pub"
  flavor_id           = "flavor-d2-2"
  image_id            = "img-new"
  lb_flavor_id        = "lb-small"
}

run "defaults" {
  command = plan

  assert {
    condition     = local.app_names == ["akairos-app-1", "akairos-app-2"]
    error_message = "two prefixed app names by default"
  }
  assert {
    condition     = strcontains(base64decode(ovh_cloud_instance.bastion.user_data), "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKeyOnlyForOfflineTests")
    error_message = "SSH public key injected by cloud-init"
  }
}

run "admin_cidr_without_mask" {
  command = plan
  variables { admin_cidr = "203.0.113.7" }
  expect_failures = [var.admin_cidr]
}

run "too_many_instances" {
  command = plan
  variables { instance_count = 6 }
  expect_failures = [var.instance_count]
}

run "network" {
  command = plan

  assert {
    condition     = ovh_cloud_network_private_vrack.this.name == "akairos-net" && ovh_cloud_network_private_vrack.this.vlan_id == 42
    error_message = "network name/vlan"
  }
  assert {
    condition     = ovh_cloud_network_private_vrack_subnet.this.cidr == "10.42.0.0/24"
    error_message = "subnet cidr"
  }
  assert {
    condition     = ovh_cloud_gateway.this.name == "akairos-gw" && ovh_cloud_gateway.this.external_gateway.model == "S"
    error_message = "gateway model S (API v2 casing)"
  }
}

run "app_instances_private_only" {
  command = plan
  variables { instance_count = 3 }

  assert {
    condition     = length(ovh_cloud_instance.app) == 3 && ovh_cloud_instance.app[2].name == "akairos-app-3"
    error_message = "three app instances"
  }
  assert {
    condition = alltrue([for i in ovh_cloud_instance.app : alltrue([
      for n in i.networks : n.auto_assign_public_ip != true && n.ip == null
    ])])
    error_message = "app instances: private interface only, no public IP, no floating IP"
  }
  assert {
    condition     = strcontains(base64decode(ovh_cloud_instance.app[0].user_data), "location = /health") && strcontains(base64decode(ovh_cloud_instance.app[0].user_data), "NAME=\"akairos-app-1\"")
    error_message = "app cloud-init (base64) serves /health and its own name"
  }
}

run "bastion" {
  command = apply

  assert {
    condition     = length(ovh_cloud_instance.bastion.networks) == 1 && ovh_cloud_instance.bastion.networks[0].ip == "198.51.100.20"
    error_message = "bastion: single private interface carrying its floating IP"
  }
  assert {
    condition     = strcontains(base64decode(ovh_cloud_instance.bastion.user_data), "ssh_pwauth: false")
    error_message = "password SSH disabled"
  }
  assert {
    condition = length([for r in ovh_cloud_security_group.bastion.rule : r
    if r.direction == "INGRESS" && r.remote_ip_prefix == "203.0.113.7/32" && r.port_range_min == 22 && r.protocol == "TCP"]) == 1
    error_message = "bastion SSH only from admin_cidr"
  }
  assert {
    condition     = length([for r in ovh_cloud_security_group.bastion.rule : r if r.direction == "INGRESS"]) == 1
    error_message = "no other ingress on bastion"
  }
}

run "lb_wiring" {
  command = apply
  variables { instance_count = 3 }

  assert {
    condition     = ovh_cloud_project_loadbalancer.this.network.private.floating_ip.id == "fip-uuid"
    error_message = "LB uses the Terraform-managed floating IP (deleted on destroy)"
  }
  assert {
    condition     = length(ovh_cloud_project_loadbalancer.this.listeners[0].pool.members) == 3
    error_message = "one member per instance"
  }
  assert {
    condition = (
      ovh_cloud_project_loadbalancer.this.listeners[0].port == 80 &&
      ovh_cloud_project_loadbalancer.this.listeners[0].pool.health_monitor.http_configuration.url_path == "/health" &&
      ovh_cloud_project_loadbalancer.this.listeners[0].pool.health_monitor.http_configuration.expected_codes == "200"
    )
    error_message = "HTTP:80 with /health monitor"
  }
}

run "ssh_config" {
  command = apply

  assert {
    condition     = strcontains(output.ssh_config, "ProxyJump akairos-bastion") && strcontains(output.ssh_config, "Host akairos-app-2") && strcontains(output.ssh_config, "HostName 198.51.100.20")
    error_message = "ssh_config goes through the bastion floating IP"
  }
}
