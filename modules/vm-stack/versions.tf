terraform {
  required_version = ">= 1.9"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.24"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}
