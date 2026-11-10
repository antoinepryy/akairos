# Terraform state in the client's Object Storage (S3 API), with lock file.
# Keys: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY of an S3 user of the client's project (env.sh).
bucket = "__PREFIX__-tfstate"
key    = "platform/terraform.tfstate"
region = "__S3_REGION__"

endpoints = {
  s3 = "https://s3.__S3_REGION__.io.cloud.ovh.net"
}

use_path_style              = true
use_lockfile                = true
skip_credentials_validation = true
skip_region_validation      = true
skip_requesting_account_id  = true
skip_s3_checksum            = true
