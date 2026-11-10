#!/usr/bin/env python3
"""List any akairos-* resource left in the project after `terraform destroy`.

Read-only (GET only). Uses OVH_APPLICATION_KEY / _SECRET / OVH_CONSUMER_KEY
from env.sh. Exit 1 if something is left, or if the backup bucket is missing.
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
KEEP_BUCKET = ("EU-WEST-PAR", "dna-backups-cronos")


def get(path):
    url = API + path
    ts = urllib.request.urlopen(API + "/auth/time").read().decode().strip()
    ak, sk, ck = (os.environ[k] for k in ("OVH_APPLICATION_KEY", "OVH_APPLICATION_SECRET", "OVH_CONSUMER_KEY"))
    sig = "$1$" + hashlib.sha1("+".join([sk, ck, "GET", url, "", ts]).encode()).hexdigest()
    req = urllib.request.Request(url, headers={
        "X-Ovh-Application": ak, "X-Ovh-Consumer": ck, "X-Ovh-Timestamp": ts, "X-Ovh-Signature": sig})
    try:
        return json.loads(urllib.request.urlopen(req).read() or "null")
    except urllib.error.HTTPError as e:
        print(f"  ! GET {path}: HTTP {e.code}", file=sys.stderr)
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

    region, bucket = KEEP_BUCKET
    buckets = [b.get("name") for b in get(f"{base}/region/{region}/storage") or []]
    bucket_ok = bucket in buckets

    for line in left:
        print("LEFT  " + line)
    print(f"bucket {bucket}: {'present' if bucket_ok else 'MISSING'}")
    if left or not bucket_ok:
        sys.exit(1)
    print("nothing left")


if __name__ == "__main__":
    main()
