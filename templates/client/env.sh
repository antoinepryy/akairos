# shellcheck shell=bash
# Source me: `source env.sh`. Contains no secret: values come from
# ~/.config/infra/secrets.env, under the names below.
SECRETS="${SECRETS:-$HOME/.config/infra/secrets.env}"
if [ -f "$SECRETS" ]; then set -a; . "$SECRETS"; set +a; fi

export OVH_CLIENT_ID="${__ENV__CLIENT_ID:?missing __ENV__CLIENT_ID in $SECRETS}"
export OVH_CLIENT_SECRET="${__ENV__CLIENT_SECRET:?missing __ENV__CLIENT_SECRET}"
export AWS_ACCESS_KEY_ID="${__ENV__S3_ACCESS_KEY:?missing __ENV__S3_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${__ENV__S3_SECRET_KEY:?missing __ENV__S3_SECRET_KEY}"
# Optional: deploy key of the repository, for Argo CD.
if [ -n "${__ENV__DEPLOY_KEY_FILE:-}" ]; then
  TF_VAR_git_ssh_private_key="$(cat "$__ENV__DEPLOY_KEY_FILE")"; export TF_VAR_git_ssh_private_key
fi
unset OVH_APPLICATION_KEY OVH_APPLICATION_SECRET OVH_CONSUMER_KEY
export OVH_ENDPOINT="${OVH_ENDPOINT_OVERRIDE:-ovh-eu}"

# Same values for check-leftovers.py (akairos repository).
export TF_VAR_service_name="__PROJECT_ID__" TF_VAR_region="__REGION__" TF_VAR_prefix="__PREFIX__"

if ip="$(curl -fsS --max-time 5 https://api.ipify.org)"; then
  export TF_VAR_admin_cidr="$ip/32"; echo "admin_cidr = $TF_VAR_admin_cidr"
else
  echo "Could not detect the public IP; export TF_VAR_admin_cidr=<ip>/32 yourself." >&2
fi
