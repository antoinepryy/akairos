#!/usr/bin/env bash
# Write the cluster's kubeconfig to k8s/kubeconfig.yml (git-ignored, mode 600).
# Usage: eval "$(scripts/k8s-kubeconfig.sh)"   -> exports KUBECONFIG
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/k8s/kubeconfig.yml"
# Private temporary file, replaced only once terraform succeeded: an error
# never empties a working kubeconfig, and an old 644 file ends up 600.
umask 077
tmp="$(mktemp "$out.XXXXXX")"; trap 'rm -f "$tmp"' EXIT
terraform -chdir="$root/k8s" output -raw kubeconfig > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$out"
printf 'export KUBECONFIG=%q\n' "$out"
