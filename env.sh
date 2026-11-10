# shellcheck shell=bash
# Source me: `source env.sh`. Contains no secret.
# Auth: an OVH service account (OAuth2 client credentials) whose IAM policy is
# limited to the Public Cloud project. Legacy application keys cannot carry the
# IAM identity some v2 actions require (e.g. loadbalancer/usePublicIP).
# A trainee exports OVH_CLIENT_ID / OVH_CLIENT_SECRET themselves (see README).

if [ -f "$HOME/.config/infra/secrets.env" ] && [ -z "${OVH_CLIENT_ID:-}" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$HOME/.config/infra/secrets.env"
  set +a
  export OVH_CLIENT_ID="$OVH_AKAIROS_CLIENT_ID"
  export OVH_CLIENT_SECRET="$OVH_AKAIROS_CLIENT_SECRET"
  # Antoine's project also holds the off-site backups: check they survive.
  export CHECK_BUCKET="${CHECK_BUCKET:-EU-WEST-PAR/dna-backups-cronos}"
fi
# Only one auth method for the provider.
unset OVH_APPLICATION_KEY OVH_APPLICATION_SECRET OVH_CONSUMER_KEY
export OVH_ENDPOINT="${OVH_ENDPOINT_OVERRIDE:-ovh-eu}"

# Same values for terraform and scripts/check-leftovers.py (override before sourcing).
export TF_VAR_region="${TF_VAR_region:-GRA11}"
export TF_VAR_prefix="${TF_VAR_prefix:-akairos}"

if ip="$(curl -fsS --max-time 5 https://api.ipify.org)"; then
  export TF_VAR_admin_cidr="$ip/32"
  echo "admin_cidr = $TF_VAR_admin_cidr"
else
  echo "Could not detect the public IP; export TF_VAR_admin_cidr=<ip>/32 yourself." >&2
fi
