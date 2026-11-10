# The key fingerprint is part of the name: a new key gives a new name, which
# replaces the instances (ssh_key_name is immutable and only injected at boot),
# so an old key never stays authorized by accident.
resource "ovh_cloud_ssh_key" "this" {
  service_name = var.service_name
  name         = "${var.prefix}-key-${substr(sha256(local.ssh_public_key), 0, 8)}"
  public_key   = local.ssh_public_key
}

# Public entry point of the bastion. One private interface only (default route
# through the gateway), the floating IP is NATed on it: no dual-homing.
resource "ovh_cloud_floating_ip" "bastion" {
  service_name = var.service_name
  region       = var.region
  description  = "${var.prefix}-bastion-fip"
  depends_on   = [ovh_cloud_gateway.this]
}

resource "ovh_cloud_instance" "bastion" {
  service_name       = var.service_name
  region             = var.region
  name               = "${var.prefix}-bastion"
  flavor_id          = local.flavor_id
  image_id           = local.image_id
  ssh_key_name       = ovh_cloud_ssh_key.this.name
  security_group_ids = [ovh_cloud_security_group.bastion.id]
  user_data          = filebase64("${path.module}/templates/bastion.yaml")

  networks = [{
    network_id = ovh_cloud_network_private_vrack.this.id
    subnet_id  = ovh_cloud_network_private_vrack_subnet.this.id
    ip         = ovh_cloud_floating_ip.bastion.current_state.ip
  }]

  lifecycle {
    # A newer catalog image must not rebuild a running demo (image_id change
    # wipes the root disk). Change images with -replace explicitly.
    ignore_changes = [image_id]
  }
}

resource "ovh_cloud_instance" "app" {
  count = var.instance_count

  service_name       = var.service_name
  region             = var.region
  name               = local.app_names[count.index]
  flavor_id          = local.flavor_id
  image_id           = local.image_id
  ssh_key_name       = ovh_cloud_ssh_key.this.name
  security_group_ids = [ovh_cloud_security_group.app.id]

  user_data = base64encode(templatefile("${path.module}/templates/app.yaml.tftpl", {
    name = local.app_names[count.index]
  }))

  # Private only: no public interface, no floating IP. Egress through the gateway.
  networks = [{
    network_id = ovh_cloud_network_private_vrack.this.id
    subnet_id  = ovh_cloud_network_private_vrack_subnet.this.id
    ip         = local.app_ips[count.index]
  }]

  lifecycle {
    ignore_changes = [image_id]
  }

  depends_on = [ovh_cloud_gateway.this]
}
