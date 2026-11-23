#!/usr/bin/env bash
# Write the cluster's kubeconfig to <dir>/kubeconfig.yml (git-ignored, mode 600).
# Usage: eval "$(scripts/k8s-kubeconfig.sh)"           -> k8s/ (level 2)
#        eval "$(scripts/k8s-kubeconfig.sh bedrock)"   -> bedrock/
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
dir="${1:-k8s}"
case "$dir" in k8s|bedrock) ;; *) echo "usage: $0 [k8s|bedrock]" >&2; exit 2 ;; esac
out="$root/$dir/kubeconfig.yml"
# Private temporary file, replaced only once terraform succeeded: an error
# never empties a working kubeconfig, and an old 644 file ends up 600.
umask 077
tmp="$(mktemp "$out.XXXXXX")"; trap 'rm -f "$tmp"' EXIT
terraform -chdir="$root/$dir" output -raw kubeconfig > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$out"
printf 'export KUBECONFIG=%q\n' "$out"
