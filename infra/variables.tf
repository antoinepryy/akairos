variable "service_name" {
  description = "OVH Public Cloud project id (default: D&A Engineering)."
  type        = string
  default     = "120a120c626c48d28773c56e42bce375"
}

variable "region" {
  # GRA11 ran out of d2 capacity on 2026-11-10 ("No valid host was found").
  description = "OpenStack region where everything is created."
  type        = string
  default     = "SBG5"
}

variable "prefix" {
  description = "Prefix of every resource name, used to find leftovers."
  type        = string
  default     = "akairos"
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

variable "ssh_public_key_path" {
  description = "Public key installed on every instance."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
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
