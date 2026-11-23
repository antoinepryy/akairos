#!/usr/bin/env bash
# Create the Secret bedrock-env in namespace bedrock: what the public chart
# apps/bedrock may not hold (DB password, WordPress salts, admin password, S3
# keys). Run once after the apply; Argo CD's pods wait for it. Never overwrites
# an existing Secret (new salts would log everybody out, a new DB password
# would no longer match the database).
# Needs KUBECONFIG (eval "$(scripts/k8s-kubeconfig.sh bedrock)").
# From ~/.config/infra/secrets.env, read one by one in a subshell: the S3 keys
# of the Swarm demo (BEDROCK_S3_ACCESS / BEDROCK_S3_SECRET, user limited to the
# media bucket) and BEDROCK_WP_ADMIN_PASSWORD. A trainee exports them instead.
set -euo pipefail
ns=bedrock
secret() {
  if [ -n "${!1:-}" ]; then printf '%s' "${!1}"; return; fi
  # shellcheck disable=SC1090,SC1091
  ( . "$HOME/.config/infra/secrets.env" >/dev/null 2>&1; eval "printf '%s' \"\${$1:-}\"" )
}

kubectl get namespace "$ns" >/dev/null 2>&1 || kubectl create namespace "$ns" >/dev/null
if kubectl -n "$ns" get secret bedrock-env >/dev/null 2>&1; then
  echo "secret $ns/bedrock-env already exists, left as is"; exit 0
fi

s3_access="$(secret BEDROCK_S3_ACCESS)"; s3_secret="$(secret BEDROCK_S3_SECRET)"
admin="$(secret BEDROCK_WP_ADMIN_PASSWORD)"
[ -n "$s3_access" ] && [ -n "$s3_secret" ] || { echo "BEDROCK_S3_ACCESS / BEDROCK_S3_SECRET missing" >&2; exit 1; }
[ -n "$admin" ] || { echo "BEDROCK_WP_ADMIN_PASSWORD missing" >&2; exit 1; }

# Values through a private file, not the command line (visible in ps).
umask 077
env_file="$(mktemp)"; trap 'rm -f "$env_file"' EXIT
{
  echo "DB_PASSWORD=$(openssl rand -hex 24)"
  echo "WP_ADMIN_PASSWORD=$admin"
  echo "S3_UPLOADS_KEY=$s3_access"
  echo "S3_UPLOADS_SECRET=$s3_secret"
  for k in AUTH_KEY SECURE_AUTH_KEY LOGGED_IN_KEY NONCE_KEY AUTH_SALT SECURE_AUTH_SALT LOGGED_IN_SALT NONCE_SALT; do
    echo "$k=$(openssl rand -hex 32)"
  done
} > "$env_file"
kubectl -n "$ns" create secret generic bedrock-env --from-env-file="$env_file" >/dev/null
echo "secret $ns/bedrock-env created"
