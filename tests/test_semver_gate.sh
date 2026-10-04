#!/usr/bin/env bash
# Tests dependabot-review/semver-gate.sh against fixed Dependabot metadata.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=dependabot-review/semver-gate.sh
failures=0

dep() {
  printf '{"dependencyName":"%s","updateType":%s}' "$1" "$2"
}

# expect <name> <pass or block> <updated-dependencies-json> [substring of the reason]
expect() {
  local name=$1 want=$2 json=$3 reason=${4:-}
  local out got
  if out=$(UPDATED_DEPENDENCIES_JSON=$json "$script" 2>/dev/null); then
    got=pass
  else
    got=block
  fi
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: want $want, got $got"
    failures=$((failures + 1))
  elif [ -n "$reason" ] && [[ "$out" != *"$reason"* ]]; then
    echo "FAIL $name: reason '$out' lacks '$reason'"
    failures=$((failures + 1))
  elif [ "$got" = pass ] && [ -n "$out" ]; then
    echo "FAIL $name: pass printed '$out'"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

patch='"version-update:semver-patch"'
minor='"version-update:semver-minor"'
major='"version-update:semver-major"'

expect allows_patch_and_minor pass "[$(dep a "$patch"),$(dep b "$minor")]"
expect blocks_major_in_group block "[$(dep a "$patch"),$(dep b "$major")]" "Major update: b"
expect blocks_null_update_type block "[$(dep a null)]" "Update type unknown: a"
expect blocks_empty_list block "[]" "Could not read Dependabot metadata"
expect blocks_invalid_json block "not json" "Could not read Dependabot metadata"
expect blocks_unset block "" "Could not read Dependabot metadata"

exit $((failures > 0))
