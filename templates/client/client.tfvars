# Non-secret settings of __CLIENT__ (committed). Secrets come from env.sh.
service_name = "__PROJECT_ID__"
region       = "__REGION__"
prefix       = "__PREFIX__"
git_repo_url = "git@github.com:__GITHUB_REPO__.git"

# Production profile by default. For a test: cluster_plan = "free",
# private_nodes = false, node_flavor = "d2-4", node_count = 2.
# Pinned Kubernetes minor version (versions offered: OVH API
# GET /cloud/project/{id}/capabilities/kube/versions). Upgrade on purpose.
kube_version  = "1.35"
cluster_plan  = "standard"
private_nodes = true
node_flavor   = "b3-8"
node_count    = 3
