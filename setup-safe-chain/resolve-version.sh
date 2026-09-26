#!/usr/bin/env bash
# Prints the tag of the newest Aikido Safe Chain release that is published,
# stable, immutable, and at least COOLDOWN_HOURS old.
#
# SAFE_CHAIN_RELEASES_FILE replaces the GitHub API response with a local JSON
# file, for tests.
set -euo pipefail

if ! [[ "${COOLDOWN_HOURS:-}" =~ ^[0-9]+$ ]]; then
  echo "COOLDOWN_HOURS must be a non-negative integer, got '${COOLDOWN_HOURS:-}'" >&2
  exit 1
fi

if [ -n "${SAFE_CHAIN_RELEASES_FILE:-}" ]; then
  releases=$(cat "$SAFE_CHAIN_RELEASES_FILE")
else
  releases=$(gh api 'repos/AikidoSec/safe-chain/releases?per_page=100')
fi

tag=$(jq -r --argjson hours "$COOLDOWN_HOURS" '
  [.[]
    | select((.draft | not) and (.prerelease | not) and .immutable)
    | select((.published_at | fromdateiso8601) <= (now - $hours * 3600))]
  | sort_by(.published_at) | last | .tag_name // empty
' <<<"$releases")

if [ -z "$tag" ]; then
  echo "No immutable Safe Chain release is at least ${COOLDOWN_HOURS} hours old" >&2
  exit 1
fi
echo "$tag"
