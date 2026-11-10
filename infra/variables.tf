variable "service_name" {
  description = "OVH Public Cloud project id (default: D&A Engineering)."
  type        = string
  default     = "120a120c626c48d28773c56e42bce375"
}

variable "region" {
  type    = string
  default = "SBG5"
}

variable "prefix" {
  type    = string
  default = "akairos"
}

variable "admin_cidr" {
  description = "CIDR allowed to SSH into the bastion (env.sh sets it to the current public IP)."
  type        = string
}

variable "instance_count" {
  type    = number
  default = 2
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "flavor_name" {
  type    = string
  default = "d2-2"
}

variable "image_name" {
  type    = string
  default = "Debian 13"
}

variable "image_id" {
  type    = string
  default = null
}
