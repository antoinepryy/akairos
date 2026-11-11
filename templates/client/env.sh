# shellcheck shell=bash
# Source me: `source env.sh`. Contains no secret: values come from
# ~/.config/infra/secrets.env, under the names below.
SECRETS="${SECRETS:-$HOME/.config/infra/secrets.env}"
# Only this client's values leave the secrets file (read in a subshell): the
# secrets of other clients never reach this shell nor terraform.
_secret() {
  # shellcheck disable=SC1090,SC1091
  [ -f "$SECRETS" ] && ( . "$SECRETS" >/dev/null 2>&1; eval "printf '%s' \"\${$1:-}\"" )
}
_require() {
  _v="$(_secret "$2")"
  if [ -z "$_v" ]; then echo "missing $2 in $SECRETS" >&2; return 1; fi
  export "$1=$_v"; unset _v
}
_require OVH_CLIENT_ID __ENV__CLIENT_ID || return 1
_require OVH_CLIENT_SECRET __ENV__CLIENT_SECRET || return 1
_require AWS_ACCESS_KEY_ID __ENV__S3_ACCESS_KEY || return 1
_require AWS_SECRET_ACCESS_KEY __ENV__S3_SECRET_KEY || return 1
# Optional: deploy key of the repository, for Argo CD.
_key_file="$(_secret __ENV__DEPLOY_KEY_FILE)"
if [ -n "$_key_file" ]; then
  TF_VAR_git_ssh_private_key="$(cat "$_key_file")"; export TF_VAR_git_ssh_private_key
fi
unset _key_file
unset OVH_APPLICATION_KEY OVH_APPLICATION_SECRET OVH_CONSUMER_KEY
export OVH_ENDPOINT="${OVH_ENDPOINT_OVERRIDE:-ovh-eu}"

# Same values for check-leftovers.py (akairos repository).
export TF_VAR_service_name="__PROJECT_ID__" TF_VAR_region="__REGION__" TF_VAR_prefix="__PREFIX__"

if ip="$(curl -fsS --max-time 5 https://api.ipify.org)"; then
  export TF_VAR_admin_cidr="$ip/32"; echo "admin_cidr = $TF_VAR_admin_cidr"
else
  echo "Could not detect the public IP; export TF_VAR_admin_cidr=<ip>/32 yourself." >&2
fi
