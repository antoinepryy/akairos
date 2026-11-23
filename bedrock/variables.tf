variable "service_name" {
  description = "OVH Public Cloud project id (default: D&A Engineering)."
  type        = string
  default     = "120a120c626c48d28773c56e42bce375"
}

variable "region" {
  type    = string
  default = "SBG5"
}

variable "admin_cidr" {
  description = "Only CIDR allowed to reach the Kubernetes API (env.sh sets it to the current public IP)."
  type        = string
}

# Three nodes: one Galera pod per node, the cluster keeps writing with two.
variable "node_count" {
  type    = number
  default = 3
}

# d2-8 (4 vCPU, 8 GB), as the Swarm nodes: Argo CD, Traefik, cert-manager,
# the operator, 3 Galera and 3 WordPress fit with room for a node loss.
variable "node_flavor" {
  type    = string
  default = "d2-8"
}

variable "git_repo_url" {
  description = "Public repository Argo CD deploys from (a trainee points it to their fork)."
  type        = string
  default     = "https://github.com/antoinepryy/akairos.git"
}

variable "git_revision" {
  type    = string
  default = "bedrock"
}

variable "traefik_chart_version" {
  type    = string
  default = "42.4.1"
}

variable "cert_manager_chart_version" {
  type    = string
  default = "v1.21.3"
}

# Keep in step with galera.operatorImage in apps/bedrock/values.yaml.
variable "mariadb_operator_chart_version" {
  type    = string
  default = "26.10.2"
}

variable "destroy_guard" {
  description = "Wait for the load balancers and volumes to be gone before destroying the cluster. Only the offline tests turn it off."
  type        = bool
  default     = true
}
