# Offline tests: mocked provider, plan only. Nothing is created at OVH.
mock_provider "ovh" {}

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
    condition     = local.app_ips == ["10.42.0.10", "10.42.0.11"]
    error_message = "two app IPs from .10 by default"
  }
  assert {
    condition     = local.bastion_ip == "10.42.0.5"
    error_message = "bastion on .5"
  }
  assert {
    condition     = local.app_names[1] == "akairos-app-2"
    error_message = "app names prefixed"
  }
  assert {
    condition     = local.flavor_id == "flavor-d2-2" && local.image_id == "img-new" && local.lb_flavor_id == "lb-small"
    error_message = "smallest flavors and newest Debian 12 image"
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
    condition     = ovh_cloud_network_private_vrack_subnet.this.cidr == "10.42.0.0/24" && ovh_cloud_network_private_vrack_subnet.this.allocation_pools[0].start == "10.42.0.100"
    error_message = "subnet cidr and DHCP pool"
  }
  assert {
    condition     = ovh_cloud_gateway.this.name == "akairos-gw" && ovh_cloud_gateway.this.external_gateway.model == "s"
    error_message = "gateway"
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
      for n in i.networks : n.auto_assign_public_ip != true && n.ip != null
    ])])
    error_message = "app instances must have no public interface"
  }
  assert {
    condition     = strcontains(ovh_cloud_instance.app[0].user_data, "location = /health") && strcontains(ovh_cloud_instance.app[0].user_data, "NAME=\"akairos-app-1\"")
    error_message = "app cloud-init serves /health and its own name"
  }
}

run "bastion" {
  command = plan

  assert {
    condition     = length([for n in ovh_cloud_instance.bastion.networks : n if n.auto_assign_public_ip == true]) == 1
    error_message = "bastion has exactly one public interface"
  }
  assert {
    condition     = strcontains(ovh_cloud_instance.bastion.user_data, "ssh_pwauth: false")
    error_message = "password SSH disabled"
  }
  assert {
    condition = length([for r in ovh_cloud_security_group.bastion.rule : r
    if r.direction == "ingress" && r.remote_ip_prefix == "203.0.113.7/32" && r.port_range_min == 22]) == 1
    error_message = "bastion SSH only from admin_cidr"
  }
  assert {
    condition     = length([for r in ovh_cloud_security_group.bastion.rule : r if r.direction == "ingress"]) == 1
    error_message = "no other ingress on bastion"
  }
}

run "members_follow_count_up" {
  command = plan
  variables { instance_count = 3 }

  assert {
    condition     = length(ovh_cloud_project_loadbalancer.this.listeners[0].pool.members) == 3
    error_message = "3 members"
  }
}

run "members_follow_count_down" {
  command = plan
  variables { instance_count = 2 }

  assert {
    condition     = length(ovh_cloud_project_loadbalancer.this.listeners[0].pool.members) == 2 && ovh_cloud_project_loadbalancer.this.listeners[0].pool.members[1].address == "10.42.0.11"
    error_message = "2 members, second on .11"
  }
}

run "health_monitor" {
  command = plan

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
  # Mocked apply: outputs need the (fake) bastion address.
  command = apply

  assert {
    condition     = strcontains(output.ssh_config, "ProxyJump akairos-bastion") && strcontains(output.ssh_config, "Host akairos-app-2")
    error_message = "ssh_config goes through the bastion"
  }
}
