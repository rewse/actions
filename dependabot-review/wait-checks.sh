#!/usr/bin/env bash
# Polls the checks of a PR until every check outside OWN_WORKFLOW finishes and
# prints pass, fail, none, or timeout. Until NONE_GRACE_SECONDS have passed, no
# checks counts as pending, since other workflows may not have registered yet.
#
# Usage: wait-checks.sh <pr-number>
set -euo pipefail

poll_seconds=${POLL_SECONDS:-30}
timeout_seconds=${TIMEOUT_SECONDS:-1800}
none_grace_seconds=${NONE_GRACE_SECONDS:-300}
dir=$(dirname "$0")
SECONDS=0

while :; do
  # gh exits non-zero while checks are pending or failing, so only its output
  # matters here.
  checks=$(gh pr checks "$1" --json name,workflow,bucket 2>/dev/null || true)
  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$checks"; then
    checks='[]'
  fi
  state=$("$dir/check-status.sh" <<<"$checks")
  if [ "$state" = none ] && [ "$SECONDS" -lt "$none_grace_seconds" ]; then
    state=pending
  fi
  if [ "$state" != pending ]; then
    echo "$state"
    exit 0
  fi
  if [ "$SECONDS" -ge "$timeout_seconds" ]; then
    echo timeout
    exit 0
  fi
  sleep "$poll_seconds"
done
