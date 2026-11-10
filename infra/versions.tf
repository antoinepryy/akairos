terraform {
  required_version = ">= 1.9"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.24"
    }
  }
}

# Credentials come from the environment (see ../env.sh):
# OVH_ENDPOINT, OVH_APPLICATION_KEY, OVH_APPLICATION_SECRET, OVH_CONSUMER_KEY.
provider "ovh" {}
