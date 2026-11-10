#!/usr/bin/env bash
# Destroy-time guard (called by terraform_data.wait_app_gone in argocd.tf).
# Waits until namespace $APP_NAMESPACE (default web) holds no Service: a Service of type LoadBalancer
# only disappears once OVH has deleted its load balancer. A kubectl error never
# counts as "gone": after the timeout the destroy stops, the cluster is kept.
# Input: KUBECONFIG_CONTENT. Optional: WAIT_TRIES (default 120), WAIT_SLEEP (5).
set -euo pipefail
[ "${GUARD_ENABLED:-true}" = "false" ] && { echo "destroy guard disabled"; exit 0; }
command -v kubectl >/dev/null || { echo "kubectl is required to destroy level 2" >&2; exit 1; }
cfg="$(mktemp)"; trap 'rm -f "$cfg" "$cfg.err"' EXIT
printf '%s' "$KUBECONFIG_CONTENT" > "$cfg"
last=""
ns="${APP_NAMESPACE:-web}"
for _ in $(seq "${WAIT_TRIES:-120}"); do
  if left="$(kubectl --kubeconfig "$cfg" -n "$ns" get svc -o name 2>"$cfg.err")"; then
    if [ -z "$left" ]; then echo "no Service left in namespace $ns"; exit 0; fi
    last="still present: $left"
  else
    last="kubectl error: $(cat "$cfg.err")"
  fi
  sleep "${WAIT_SLEEP:-5}"
done
echo "giving up, $last. Check the load balancers at OVH before destroying the cluster." >&2
exit 1
