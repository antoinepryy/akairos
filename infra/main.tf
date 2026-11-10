# Level 1 of the training demo: the vm-stack module with D&A Engineering's values.
# A client gets its own repository instead (see templates/client).
terraform {
  required_version = ">= 1.9"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.24"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

# Credentials come from the environment (see ../env.sh): OVH_CLIENT_ID / OVH_CLIENT_SECRET.
provider "ovh" {}

module "vm" {
  source = "../modules/vm-stack"

  service_name   = var.service_name
  region         = var.region
  prefix         = var.prefix
  admin_cidr     = var.admin_cidr
  instance_count = var.instance_count
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))
  flavor_name    = var.flavor_name
  image_name     = var.image_name
  image_id       = var.image_id
}
