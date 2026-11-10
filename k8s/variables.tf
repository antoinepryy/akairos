variable "service_name" {
  description = "OVH Public Cloud project id (default: D&A Engineering)."
  type        = string
  default     = "120a120c626c48d28773c56e42bce375"
}

variable "region" {
  description = "Region of the Managed Kubernetes cluster and its network."
  type        = string
  default     = "SBG5"
}

variable "prefix" {
  description = "Prefix of every resource name (\"<prefix>-k8s-...\"), used to find leftovers."
  type        = string
  default     = "akairos"
}

variable "admin_cidr" {
  description = "Only CIDR (besides the cluster's own gateway) allowed to reach the Kubernetes API, e.g. 203.0.113.7/32."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.admin_cidr))
    error_message = "admin_cidr must be an IPv4 CIDR such as 203.0.113.7/32."
  }
}

variable "node_count" {
  description = "Worker nodes, each on a different physical host (anti-affinity caps it at 5)."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 2 && var.node_count <= 5
    error_message = "node_count must be between 2 and 5."
  }
}

variable "node_flavor" {
  # Smallest flavor Managed Kubernetes accepts in SBG5 (d2-2 is refused).
  description = "Flavor of the worker nodes."
  type        = string
  default     = "d2-4"
}

variable "subnet_cidr" {
  description = "Private subnet on the vRack (distinct from level 1's 10.42.0.0/24)."
  type        = string
  default     = "10.43.0.0/24"
}

variable "vlan_id" {
  description = "vRack VLAN id (level 1 uses 42)."
  type        = number
  default     = 43
}

variable "git_repo_url" {
  description = "Public git repository Argo CD deploys from (a trainee points it to their fork)."
  type        = string
  default     = "https://github.com/antoinepryy/akairos.git"
}

variable "git_revision" {
  description = "Branch, tag or commit Argo CD follows."
  type        = string
  default     = "main"
}

variable "app_path" {
  description = "Path of the Helm chart inside the repository."
  type        = string
  default     = "apps/web"
}

variable "argocd_chart_version" {
  type    = string
  default = "10.17.1"
}

variable "argocd_apps_chart_version" {
  type    = string
  default = "2.0.8"
}
