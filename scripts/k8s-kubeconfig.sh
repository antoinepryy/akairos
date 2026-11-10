#!/usr/bin/env bash
# Write the cluster's kubeconfig to k8s/kubeconfig.yml (git-ignored, chmod 600).
# Usage: eval "$(scripts/k8s-kubeconfig.sh)"   -> exports KUBECONFIG
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/k8s/kubeconfig.yml"
umask 077
terraform -chdir="$root/k8s" output -raw kubeconfig > "$out"
echo "export KUBECONFIG=$out"
