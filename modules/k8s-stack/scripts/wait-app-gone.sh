#!/usr/bin/env bash
# Destroy-time guard (terraform_data.wait_app_gone in argocd.tf runs its
# content with bash -c, so it must not rely on its own path).
# Waits until the Argo CD Application $APP_NAME is fully deleted (its finalizer
# removes everything it deployed) and namespace $APP_NAMESPACE holds no
# Service: a Service of type LoadBalancer only disappears once OVH has deleted
# its load balancer. A kubectl error never counts as "gone": after the timeout
# the destroy stops, the cluster is kept.
# Input: KUBECONFIG_CONTENT. Optional: APP_NAME, APP_NAMESPACE (default web),
# WAIT_TRIES (default 120), WAIT_SLEEP (5).
set -euo pipefail
[ "${GUARD_ENABLED:-true}" = "false" ] && { echo "destroy guard disabled"; exit 0; }
command -v kubectl >/dev/null || { echo "kubectl is required to destroy level 2" >&2; exit 1; }
cfg="$(mktemp)"; trap 'rm -f "$cfg" "$cfg.err"' EXIT
printf '%s' "$KUBECONFIG_CONTENT" > "$cfg"
k() { kubectl --kubeconfig "$cfg" --request-timeout=10s "$@" 2>"$cfg.err"; }
last=""
ns="${APP_NAMESPACE:-web}" app="${APP_NAME:-web}"
for _ in $(seq "${WAIT_TRIES:-120}"); do
  if left_app="$(k -n argocd get applications.argoproj.io "$app" --ignore-not-found -o name)" &&
     left_svc="$(k -n "$ns" get svc -o name)"; then
    left="$(printf '%s\n%s' "$left_app" "$left_svc" | sed '/^$/d' | tr '\n' ' ')"
    if [ -z "$left" ]; then echo "application $app deleted, no Service left in namespace $ns"; exit 0; fi
    last="still present: $left"
  else
    last="kubectl error: $(cat "$cfg.err")"
  fi
  sleep "${WAIT_SLEEP:-5}"
done
echo "giving up, $last. Check the load balancers at OVH before destroying the cluster." >&2
exit 1
