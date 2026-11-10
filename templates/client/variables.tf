variable "service_name" {
  description = "Client's OVH Public Cloud project id, attached to its vRack."
  type        = string
}

variable "region" {
  type = string
}

variable "prefix" {
  description = "Prefix of every resource name, e.g. the client's short name."
  type        = string
}

variable "admin_cidr" {
  description = "Only CIDR allowed to reach the Kubernetes API (env.sh sets the operator's IP)."
  type        = string
}

variable "cluster_plan" {
  type    = string
  default = "standard"
}

variable "private_nodes" {
  type    = bool
  default = true
}

variable "node_flavor" {
  type    = string
  default = "b3-8"
}

variable "node_count" {
  type    = number
  default = 3
}

variable "subnet_cidr" {
  type    = string
  default = "10.42.0.0/24"
}

variable "vlan_id" {
  type    = number
  default = 42
}

variable "git_repo_url" {
  description = "This repository, as Argo CD reads it: git@github.com:<org>/<repo>.git if private."
  type        = string
}

variable "git_revision" {
  type    = string
  default = "main"
}

variable "git_ssh_private_key" {
  description = "Read-only deploy key of this repository (TF_VAR_git_ssh_private_key, never in a file of the repo)."
  type        = string
  default     = null
  sensitive   = true
}

variable "app_path" {
  type    = string
  default = "apps/web"
}

variable "app_name" {
  type    = string
  default = "web"
}

variable "app_namespace" {
  type    = string
  default = "web"
}
