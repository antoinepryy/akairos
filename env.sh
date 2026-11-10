# shellcheck shell=bash
# Source me: `source env.sh`. Contains no secret; maps Antoine's keys to the
# variables the OVH provider reads, and opens SSH to the current public IP.
# A trainee can instead export OVH_* themselves (see README).

if [ -f "$HOME/.config/infra/secrets.env" ] && [ -z "${OVH_APPLICATION_KEY:-}" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$HOME/.config/infra/secrets.env"
  set +a
  export OVH_APPLICATION_KEY="$OVH_FULL_APP_KEY"
  export OVH_APPLICATION_SECRET="$OVH_FULL_APP_SECRET"
  export OVH_CONSUMER_KEY="$OVH_FULL_CONSUMER_KEY"
  # Antoine's project also holds the off-site backups: check they survive.
  export CHECK_BUCKET="${CHECK_BUCKET:-EU-WEST-PAR/dna-backups-cronos}"
fi
# Same values for terraform and scripts/check-leftovers.py (override before sourcing).
export TF_VAR_region="${TF_VAR_region:-GRA11}"
export TF_VAR_prefix="${TF_VAR_prefix:-akairos}"
export OVH_ENDPOINT="${OVH_ENDPOINT_OVERRIDE:-ovh-eu}"

if ip="$(curl -fsS --max-time 5 https://api.ipify.org)"; then
  export TF_VAR_admin_cidr="$ip/32"
  echo "admin_cidr = $TF_VAR_admin_cidr"
else
  echo "Could not detect the public IP; export TF_VAR_admin_cidr=<ip>/32 yourself." >&2
fi
