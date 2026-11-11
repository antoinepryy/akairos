#!/usr/bin/env bash
# Create the repository of a new client from templates/client.
# Usage: scripts/new-client.sh <dest-dir> <client-name> <prefix> <project-id> <region> <github-org/repo> [s3-region]
# Example: scripts/new-client.sh ~/IdeaProjects/acme-platform "ACME" acme 0123abcd... SBG5 acme-corp/platform sbg
# The template is taken from the latest tag (git archive), never from the working
# tree: the generated repository matches the module version it pins, and holds
# only committed files. AKAIROS_REF=<tag> overrides the tag.
set -euo pipefail
[ $# -ge 6 ] || { sed -n '2,4p' "$0" >&2; exit 2; }
dest="$1" client="$2" prefix="$3" project="$4" region="$5" repo="$6" s3_region="${7:-}"
root="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "$1" >&2; exit 2; }
[[ "$client" =~ ^[^[:cntrl:]\"]{1,60}$ ]] || fail "client name: 1 to 60 characters, no quote or control character"
[[ "$prefix" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || fail "prefix: lowercase letters, digits and dashes, 2 to 21 characters"
[[ "$project" =~ ^[0-9a-f]{32}$ ]] || fail "project id: 32 hexadecimal characters"
[[ "$region" =~ ^[A-Z][A-Z0-9-]{1,20}$ ]] || fail "region: OVH compute region in capitals, e.g. SBG5 or EU-WEST-PAR"
[[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "repository: <github-org>/<repo>"
[ ! -e "$dest" ] || fail "$dest already exists"

# Module version: latest tag of akairos (the template pins it).
ref="${AKAIROS_REF:-$(git -C "$root" describe --tags --abbrev=0 2>/dev/null || true)}"
[ -n "$ref" ] || fail "no tag in akairos: tag a release first (git tag vX.Y.Z)"
git -C "$root" rev-parse -q --verify "refs/tags/$ref" >/dev/null || fail "unknown tag $ref"
# Object Storage region: lowercase compute region without its digits (SBG5 -> sbg), unless given.
s3_region="${s3_region:-$(printf '%s' "$region" | tr '[:upper:]' '[:lower:]' | sed 's/[0-9]*$//')}"
[[ "$s3_region" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || fail "s3 region: lowercase, e.g. sbg or eu-west-par"
env_prefix="OVH_$(printf '%s' "$prefix" | tr '[:lower:]-' '[:upper:]_')_"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
git -C "$root" archive "$ref" templates/client | tar -x -C "$work"
[ -d "$work/templates/client" ] || fail "tag $ref holds no templates/client"

# Literal replacement (no sed: a client name may hold & | or \), GNU and BSD alike.
export TPL_CLIENT="$client" TPL_PREFIX="$prefix" TPL_PROJECT_ID="$project" TPL_REGION="$region" \
  TPL_S3_REGION="$s3_region" TPL_GITHUB_REPO="$repo" TPL_MODULE_REF="$ref" TPL_ENV="$env_prefix"
# shellcheck disable=SC2016 # perl code, expanded by perl
find "$work/templates/client" -type f -print0 | xargs -0 perl -pi -e '
  s/__(CLIENT|PREFIX|PROJECT_ID|REGION|S3_REGION|GITHUB_REPO|MODULE_REF|ENV)__/$ENV{"TPL_$1"}/g'
if grep -rn "__[A-Z_]*__" "$work/templates/client"; then fail "unreplaced placeholder above"; fi

mkdir -p "$(dirname "$dest")"
mv "$work/templates/client" "$dest"
git -C "$dest" init -q -b main
echo "created $dest (module $ref). Next: README.md, section 1."
