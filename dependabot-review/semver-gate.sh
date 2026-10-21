#!/usr/bin/env bash
# Exits 0 when every dependency in UPDATED_DEPENDENCIES_JSON, the
# updated-dependencies-json output of dependabot/fetch-metadata, is a patch or
# minor update. Otherwise prints the reason on one line and exits 1, so a major
# update anywhere in a grouped PR keeps the whole PR away from auto-merge.
set -euo pipefail

json=${UPDATED_DEPENDENCIES_JSON:-}

if ! jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$json"; then
  echo "Could not read Dependabot metadata"
  exit 1
fi

# block <label> <updateType regex>: exits 1 with the reason when any element
# matches. Presence decides the result, so an element with an empty or missing
# name still blocks. The reason is capped because it is posted publicly.
block() {
  local names
  if jq -e --arg filter "$2" \
    'any(.[]; .updateType | tostring | test($filter))' >/dev/null <<<"$json"; then
    names=$(jq -r --arg filter "$2" '
      [.[] | select(.updateType | tostring | test($filter))
        | (.dependencyName // "" | tostring) | if . == "" then "(unnamed)" else . end]
      | join(", ")
    ' <<<"$json")
    reason="$1: $names"
    echo "${reason:0:500}"
    exit 1
  fi
}

block "Major update" '^version-update:semver-major$'
block "Update type unknown" '^(?!version-update:semver-(patch|minor)$)'
