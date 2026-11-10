# The SSH public key is injected by cloud-init (ssh_authorized_keys), not as an
# OVH keypair: deleting a v2 ovh_cloud_ssh_key left a copy in the v1 project
# keys, and parallel first boots raced on creating the regional keypair (409).
# A new key changes user_data, which reinstalls the instances: no old key
# stays authorized.

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
  security_group_ids = [ovh_cloud_security_group.bastion.id]
  user_data = base64encode(templatefile("${path.module}/templates/bastion.yaml.tftpl", {
    ssh_public_key = local.ssh_public_key
  }))

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
  security_group_ids = [ovh_cloud_security_group.app.id]

  user_data = base64encode(templatefile("${path.module}/templates/app.yaml.tftpl", {
    name           = local.app_names[count.index]
    ssh_public_key = local.ssh_public_key
  }))

  # Private only: no public interface, no floating IP. Egress through the gateway.
  networks = [{
    network_id = ovh_cloud_network_private_vrack.this.id
    subnet_id  = ovh_cloud_network_private_vrack_subnet.this.id
  }]

  lifecycle {
    ignore_changes = [image_id]
  }

  depends_on = [ovh_cloud_gateway.this]
}
