#!/usr/bin/env bash
# Print the URL of the app's load balancer (created by Kubernetes, not Terraform).
# Waits up to 10 min for OVH to hand out the IP. Needs KUBECONFIG (scripts/k8s-kubeconfig.sh).
set -euo pipefail
for _ in $(seq 120); do
  ip="$(kubectl --request-timeout=10s -n web get svc web -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [ -n "$ip" ]; then echo "http://$ip"; exit 0; fi
  sleep 5
done
echo "no load balancer IP after 10 min (kubectl -n web describe svc web)" >&2
exit 1
