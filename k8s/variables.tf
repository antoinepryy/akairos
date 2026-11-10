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
  description = "Only CIDR allowed to reach the Kubernetes API (env.sh sets it to the current public IP)."
  type        = string
}

variable "node_count" {
  type    = number
  default = 2
}

variable "git_repo_url" {
  description = "Public repository Argo CD deploys from (a trainee points it to their fork)."
  type        = string
  default     = "https://github.com/antoinepryy/akairos.git"
}

variable "git_revision" {
  type    = string
  default = "main"
}
