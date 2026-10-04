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

names() {
  jq -r --arg filter "$1" '
    [.[] | select(.updateType | tostring | test($filter)) | .dependencyName]
    | join(", ")
  ' <<<"$json"
}

major=$(names '^version-update:semver-major$')
if [ -n "$major" ]; then
  echo "Major update: $major"
  exit 1
fi

unknown=$(names '^(?!version-update:semver-(patch|minor)$)')
if [ -n "$unknown" ]; then
  echo "Update type unknown: $unknown"
  exit 1
fi
