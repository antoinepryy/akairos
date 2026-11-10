#!/usr/bin/env bash
# Hit the load balancer N times and count which instance answered.
set -euo pipefail
n="${1:-20}"
url="$(terraform -chdir="$(dirname "$0")/../infra" output -raw lb_url)"
echo "$url, $n requests"
for _ in $(seq "$n"); do
  curl -fsS --max-time 5 "$url/" | sed -n 's:.*<h1 id="instance">\([^<]*\)</h1>.*:\1:p' || echo "(error)"
done | sort | uniq -c
