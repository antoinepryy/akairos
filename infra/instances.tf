resource "ovh_cloud_ssh_key" "this" {
  service_name = var.service_name
  name         = "${var.prefix}-key"
  public_key   = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

resource "ovh_cloud_instance" "bastion" {
  service_name       = var.service_name
  region             = var.region
  name               = "${var.prefix}-bastion"
  flavor_id          = local.flavor_id
  image_id           = local.image_id
  ssh_key_name       = ovh_cloud_ssh_key.this.name
  security_group_ids = [ovh_cloud_security_group.bastion.id]
  user_data          = file("${path.module}/templates/bastion.yaml")

  networks = [
    # Only the bastion has a public interface.
    { auto_assign_public_ip = true },
    {
      network_id = ovh_cloud_network_private_vrack.this.id
      subnet_id  = ovh_cloud_network_private_vrack_subnet.this.id
      ip         = local.bastion_ip
    },
  ]
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

  user_data = templatefile("${path.module}/templates/app.yaml.tftpl", {
    name = local.app_names[count.index]
  })

  # Private only: no public interface, no floating IP. Egress through the gateway.
  networks = [{
    network_id = ovh_cloud_network_private_vrack.this.id
    subnet_id  = ovh_cloud_network_private_vrack_subnet.this.id
    ip         = local.app_ips[count.index]
  }]

  depends_on = [ovh_cloud_gateway.this]
}
