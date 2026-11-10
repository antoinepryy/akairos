#!/usr/bin/env bash
# Hit the load balancer N times, count which instance answered.
# Exit 1 on any failed request, or if fewer than EXPECT distinct instances answered.
# Usage: scripts/verify.sh [requests=20] [expected_instances=2]
# Level 2 (Kubernetes): URL="$(scripts/k8s-url.sh)" scripts/verify.sh 30 3
set -euo pipefail
n="${1:-20}"
expect="${2:-2}"
url="${URL:-$(terraform -chdir="$(dirname "$0")/../infra" output -raw lb_url)}"
echo "$url, $n requests, expecting $expect instances"

results="$(for _ in $(seq "$n"); do
  page="$(curl -fsS --max-time 5 "$url/" 2>/dev/null)" || { echo "(http error)"; continue; }
  name="$(printf '%s' "$page" | sed -n 's:.*<h1 id="instance">\([^<]*\)</h1>.*:\1:p')"
  echo "${name:-(no instance marker)}"
done)"

printf '%s\n' "$results" | sort | uniq -c
errors="$(printf '%s\n' "$results" | grep -c '^(' || true)"
distinct="$(printf '%s\n' "$results" | grep -v '^(' | sort -u | grep -c . || true)"

if [ "$errors" -gt 0 ] || [ "$distinct" -lt "$expect" ]; then
  echo "FAIL: $errors failed requests, $distinct distinct instances (expected $expect)" >&2
  exit 1
fi
echo "OK: $distinct distinct instances"
