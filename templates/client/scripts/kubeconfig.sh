#!/usr/bin/env bash
# Write the cluster's kubeconfig to ./kubeconfig.yml (git-ignored, chmod 600).
# Usage: eval "$(scripts/kubeconfig.sh)"
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
umask 077
terraform -chdir="$root" output -raw kubeconfig > "$root/kubeconfig.yml"
echo "export KUBECONFIG=$root/kubeconfig.yml"
