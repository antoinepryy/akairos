data "ovh_cloud_instance_flavors" "this" {
  service_name = var.service_name
  region       = var.region
}

data "ovh_cloud_instance_images" "this" {
  service_name = var.service_name
  region       = var.region
}

data "ovh_cloud_project_loadbalancer_flavors" "this" {
  service_name = var.service_name
  region_name  = var.region
}

locals {
  flavor_id = var.flavor_id != null ? var.flavor_id : one(distinct([for f in data.ovh_cloud_instance_flavors.this.flavors : f.id if f.name == var.flavor_name]))

  # Newest active image named exactly var.image_name (exact match avoids
  # variants such as "Debian 13 - Docker"; created_at is ISO 8601, sorts as text).
  images     = [for i in data.ovh_cloud_instance_images.this.images : i if i.name == var.image_name && lower(i.status) == "active"]
  newest_img = try(reverse(sort([for i in local.images : i.created_at]))[0], "")
  image_id   = var.image_id != null ? var.image_id : try([for i in local.images : i.id if i.created_at == local.newest_img][0], null)

  lb_flavor_id = var.lb_flavor_id != null ? var.lb_flavor_id : one([for f in data.ovh_cloud_project_loadbalancer_flavors.this.flavors : f.id if f.name == "small"])
}
