variable "service_name" {
  description = "OVH Public Cloud project id, already attached to a vRack."
  type        = string
}

variable "region" {
  # GRA11 ran out of d2 capacity on 2026-11-10 ("No valid host was found").
  description = "OpenStack region where everything is created, e.g. SBG5."
  type        = string
}

variable "prefix" {
  description = "Prefix of every resource name, used to find leftovers."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.prefix))
    error_message = "prefix: lowercase letters, digits and dashes, 2 to 21 characters."
  }
}

variable "instance_count" {
  description = "Number of app instances behind the load balancer."
  type        = number
  default     = 2

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 5
    error_message = "instance_count must be between 1 and 5."
  }
}

variable "flavor_name" {
  # Cheapest flavor. If a region answers "No valid host was found", try another
  # region (or d2-4) rather than retrying.
  description = "Flavor of the bastion and app instances."
  type        = string
  default     = "d2-2"
}

variable "image_name" {
  description = "Exact image name the instances boot on (newest one if several)."
  type        = string
  default     = "Debian 13"
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH into the bastion, e.g. 203.0.113.7/32 (env.sh sets it to the current public IP)."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_cidr))
    error_message = "admin_cidr must be an IPv4 CIDR such as 203.0.113.7/32."
  }
}

variable "ssh_public_key" {
  description = "Public key (content, not path) installed on every instance by cloud-init."
  type        = string
}

variable "subnet_cidr" {
  description = "Private subnet on the vRack."
  type        = string
  default     = "10.42.0.0/24"
}

variable "vlan_id" {
  description = "vRack VLAN id of the private network."
  type        = number
  default     = 42
}

# Optional pins. Null = looked up from flavor_name / image_name / "small".
variable "flavor_id" {
  type    = string
  default = null
}

variable "image_id" {
  type    = string
  default = null
}

variable "lb_flavor_id" {
  type    = string
  default = null
}
