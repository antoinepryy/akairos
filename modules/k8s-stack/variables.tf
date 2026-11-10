variable "service_name" {
  description = "OVH Public Cloud project id, already attached to a vRack."
  type        = string
}

variable "region" {
  description = "Region of the Managed Kubernetes cluster and its network, e.g. SBG5."
  type        = string
}

variable "prefix" {
  description = "Prefix of every resource name (\"<prefix>-k8s-...\"), used to find leftovers."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.prefix))
    error_message = "prefix: lowercase letters, digits and dashes, 2 to 21 characters."
  }
}

variable "cluster_plan" {
  description = "Managed Kubernetes plan: free (demo) or standard (production: SLA, private nodes)."
  type        = string
  default     = "free"

  validation {
    condition     = contains(["free", "standard"], var.cluster_plan)
    error_message = "cluster_plan must be free or standard."
  }
}

variable "private_nodes" {
  description = "Nodes without any public interface (Standard plan only, set at creation)."
  type        = bool
  default     = false

  validation {
    condition     = !var.private_nodes || var.cluster_plan == "standard"
    error_message = "private_nodes requires cluster_plan = standard."
  }
}

variable "kube_version" {
  description = "Kubernetes minor version, e.g. 1.35. Null = latest offered by OVH."
  type        = string
  default     = null
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
  description = "Git repository Argo CD deploys from: https URL if public, ssh URL (git@...) with git_ssh_private_key if private."
  type        = string
}

variable "git_ssh_private_key" {
  description = "Read-only deploy key of a private repository. It ends up in the Terraform state: keep the state in a private bucket."
  type        = string
  default     = null
  sensitive   = true
}

variable "app_name" {
  description = "Name of the Argo CD Application."
  type        = string
  default     = "web"
}

variable "app_namespace" {
  description = "Namespace the Application deploys into (watched by the destroy guard)."
  type        = string
  default     = "web"
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

variable "destroy_guard" {
  description = "Wait for the app's load balancer to be gone before destroying the cluster. Only the offline tests turn it off."
  type        = bool
  default     = true
}
