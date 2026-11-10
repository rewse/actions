#!/usr/bin/env bash
# Polls the checks of a PR until every check outside OWN_WORKFLOW finishes and
# prints pass, fail, none, or timeout. Until NONE_GRACE_SECONDS have passed, no
# checks counts as pending, since other workflows may not have registered yet.
# Passing checks also count as pending while any other workflow run for
# HEAD_SHA is unfinished, since a job that waits on another job may not have a
# check yet.
#
# Usage: wait-checks.sh <pr-number>
set -euo pipefail

poll_seconds=${POLL_SECONDS:-30}
timeout_seconds=${TIMEOUT_SECONDS:-1800}
none_grace_seconds=${NONE_GRACE_SECONDS:-300}
dir=$(dirname "$0")
head_sha=${HEAD_SHA:?HEAD_SHA must be set}
gh_stderr=$(mktemp)
trap 'rm -f "$gh_stderr"' EXIT
warned=
SECONDS=0

# warn_gh_stderr: prints what gh wrote to stderr as a ::warning:: on stderr,
# since stdout carries the result, unless the last warning said the same.
warn_gh_stderr() {
  local message
  message=$(head -c 1000 "$gh_stderr")
  [ -n "$message" ] && [ "$message" != "$warned" ] || return 0
  warned=$message
  # Workflow commands end at a line break, so escape them and %.
  message=${message//'%'/%25}
  message=${message//$'\r'/%0D}
  message=${message//$'\n'/%0A}
  echo "::warning::gh pr checks did not list the checks: $message" >&2
}

# Prints true when every workflow run for HEAD_SHA outside OWN_WORKFLOW has
# completed, and false otherwise, including when the runs cannot be listed.
runs_completed() {
  gh run list --commit "$head_sha" --json workflowName,status --limit 100 2>/dev/null \
    | jq -r --arg own "$OWN_WORKFLOW" \
      'if type == "array" then all(.[]; .workflowName == $own or .status == "completed") else false end' \
      2>/dev/null || echo false
}

while :; do
  # gh exits non-zero while checks are pending or failing, so only its output
  # matters here.
  checks=$(gh pr checks "$1" --json name,workflow,bucket 2>"$gh_stderr" || true)
  if ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$checks"; then
    warn_gh_stderr
    checks='[]'
  fi
  state=$("$dir/check-status.sh" <<<"$checks")
  if [ "$state" = none ] && [ "$SECONDS" -lt "$none_grace_seconds" ]; then
    state=pending
  fi
  if [ "$state" = pass ] && [ "$(runs_completed)" != true ]; then
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
