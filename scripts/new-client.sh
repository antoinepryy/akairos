#!/usr/bin/env bash
# Create the repository of a new client from templates/client.
# Usage: scripts/new-client.sh <dest-dir> <client-name> <prefix> <project-id> <region> <github-org/repo> [s3-region]
# Example: scripts/new-client.sh ~/IdeaProjects/acme-platform "ACME" acme 0123abcd... SBG5 acme-corp/platform sbg
set -euo pipefail
[ $# -ge 6 ] || { sed -n '2,4p' "$0" >&2; exit 2; }
dest="$1" client="$2" prefix="$3" project="$4" region="$5" repo="$6" s3_region="${7:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"

[[ "$prefix" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || { echo "prefix: lowercase letters, digits and dashes, 2 to 21 characters" >&2; exit 2; }
[[ "$project" =~ ^[0-9a-f]{32}$ ]] || { echo "project id: 32 hexadecimal characters" >&2; exit 2; }
[ ! -e "$dest" ] || { echo "$dest already exists" >&2; exit 2; }

# Module version: latest tag of akairos (the template pins it).
ref="$(git -C "$root" describe --tags --abbrev=0 2>/dev/null || true)"
[ -n "$ref" ] || { echo "no tag in akairos: tag a release first (git tag vX.Y.Z)" >&2; exit 2; }
# Object Storage region: lowercase compute region without its digits (SBG5 -> sbg), unless given.
s3_region="${s3_region:-$(printf '%s' "$region" | tr '[:upper:]' '[:lower:]' | sed 's/[0-9]*$//')}"
env_prefix="OVH_$(printf '%s' "$prefix" | tr '[:lower:]-' '[:upper:]_')_"

cp -R "$root/templates/client" "$dest"
find "$dest" -type f -print0 | while IFS= read -r -d '' f; do
  sed -i '' \
    -e "s|__CLIENT__|$client|g" -e "s|__PREFIX__|$prefix|g" -e "s|__PROJECT_ID__|$project|g" \
    -e "s|__REGION__|$region|g" -e "s|__S3_REGION__|$s3_region|g" -e "s|__GITHUB_REPO__|$repo|g" \
    -e "s|__MODULE_REF__|$ref|g" -e "s|__ENV__|$env_prefix|g" "$f"
done
if grep -rn "__[A-Z_]*__" "$dest"; then echo "unreplaced placeholder above" >&2; exit 1; fi
git -C "$dest" init -q -b main
echo "created $dest (module $ref). Next: README.md, section 1."
