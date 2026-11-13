#!/usr/bin/env bash
# Prints UPDATED_DEPENDENCIES_JSON, the updated-dependencies-json output of
# dependabot/fetch-metadata, with the updateType of each Docker digest update
# set to version-update:digest. For an image whose tag stays the same and
# whose digest changes, Dependabot gives no update type, and fetch-metadata
# derives one from the short digest that it reads as the previous version and
# the tag that it reads as the new version, so it reports a semver-major
# update.
#
# A dependency counts as a digest update only when it is a Docker image, its
# previous version is a short digest, and the PR diff, given as the first
# argument, shows that the previous digest is among the removed references to
# the image, that every added or removed reference to it carries a digest, and
# that each file keeps the same tags. Anything else, including unreadable
# input, passes through unchanged, so semver-gate.sh still blocks it.
#
# Usage: UPDATED_DEPENDENCIES_JSON=<json> digest-updates.sh <diff.patch>
set -euo pipefail

json=${UPDATED_DEPENDENCIES_JSON:-}
diff_file=${1:-}

if ! [ -r "$diff_file" ] || ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$json"; then
  printf '%s\n' "$json"
  exit 0
fi

if ! out=$(jq -c --rawfile diff "$diff_file" -f "$(dirname "$0")/digest-updates.jq" <<<"$json" 2>/dev/null); then
  printf '%s\n' "$json"
  exit 0
fi
printf '%s\n' "$out"
