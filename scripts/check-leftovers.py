#!/usr/bin/env python3
"""List any akairos-* resource left in the project after `terraform destroy`.

Read-only (GET only). Uses OVH_APPLICATION_KEY / _SECRET / OVH_CONSUMER_KEY
from env.sh. Project, region and prefix come from TF_VAR_service_name,
TF_VAR_region and TF_VAR_prefix: run it with the same values as `apply`
(env.sh exports them). Exit 1 if something is left, if any API call failed
(an incomplete check is never reported as clean), or if CHECK_BUCKET is set
and that bucket is missing (env.sh sets it to the backup bucket on Antoine's Mac).
"""
import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://eu.api.ovh.com/1.0"
PROJECT = os.environ.get("TF_VAR_service_name", "120a120c626c48d28773c56e42bce375")
REGION = os.environ.get("TF_VAR_region", "GRA11")
PREFIX = os.environ.get("TF_VAR_prefix", "akairos") + "-"
# "REGION/name" of a bucket that must survive, or empty to skip the check.
CHECK_BUCKET = os.environ.get("CHECK_BUCKET", "")
ERRORS = []


def get(path):
    url = API + path
    ts = urllib.request.urlopen(API + "/auth/time").read().decode().strip()
    ak, sk, ck = (os.environ[k] for k in ("OVH_APPLICATION_KEY", "OVH_APPLICATION_SECRET", "OVH_CONSUMER_KEY"))
    sig = "$1$" + hashlib.sha1("+".join([sk, ck, "GET", url, "", ts]).encode()).hexdigest()
    req = urllib.request.Request(url, headers={
        "X-Ovh-Application": ak, "X-Ovh-Consumer": ck, "X-Ovh-Timestamp": ts, "X-Ovh-Signature": sig})
    try:
        return json.loads(urllib.request.urlopen(req).read() or "null")
    except (urllib.error.URLError, ValueError) as e:
        ERRORS.append(f"GET {path}: {e}")
        return []


def main():
    base = f"/cloud/project/{PROJECT}"
    checks = {
        "instance": f"{base}/instance",
        "private network": f"{base}/network/private",
        "ssh key": f"{base}/sshkey",
        "gateway": f"{base}/region/{REGION}/gateway",
        "load balancer": f"{base}/region/{REGION}/loadbalancing/loadbalancer",
    }
    left = []
    for kind, path in checks.items():
        for item in get(path) or []:
            if str(item.get("name", "")).startswith(PREFIX):
                left.append(f"{kind}: {item.get('name')} ({item.get('id')})")
    # Floating IPs have no name: any unattached one in the region is suspicious.
    for fip in get(f"{base}/region/{REGION}/floatingip") or []:
        if not fip.get("associatedEntity"):
            left.append(f"floating ip (unattached): {fip.get('ip')} ({fip.get('id')})")

    bucket_ok = True
    if CHECK_BUCKET:
        region, bucket = CHECK_BUCKET.split("/", 1)
        buckets = [b.get("name") for b in get(f"{base}/region/{region}/storage") or []]
        bucket_ok = bucket in buckets
        print(f"bucket {bucket}: {'present' if bucket_ok else 'MISSING'}")

    print(f"project {PROJECT}, region {REGION}, prefix {PREFIX}")
    for line in left:
        print("LEFT  " + line)
    for err in ERRORS:
        print("ERROR " + err)
    if ERRORS:
        print("INCOMPLETE: some inventories could not be read")
        sys.exit(2)
    if left or not bucket_ok:
        sys.exit(1)
    print("nothing left")


if __name__ == "__main__":
    main()
