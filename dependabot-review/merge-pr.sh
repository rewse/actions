#!/usr/bin/env bash
# Rebase-merges a PR, refusing to when its head is no longer HEAD_SHA. When
# GitHub reports that the base branch moved during the merge, which happens
# when the runs for several Dependabot PRs in one repository merge at the same
# moment, waits and tries again, up to MERGE_ATTEMPTS times in all. Any other
# error, including a head that moved, ends the attempts. Exits 0 once the PR
# is merged; otherwise prints gh's error on stderr and its first line on
# stdout, and exits 1.
#
# Usage: HEAD_SHA=<sha> merge-pr.sh <pr-number>
set -euo pipefail

attempts=${MERGE_ATTEMPTS:-4}
retry_seconds=${MERGE_RETRY_SECONDS:-15}
head_sha=${HEAD_SHA:?HEAD_SHA must be set}

for ((attempt = 1; ; attempt++)); do
  if err=$(gh pr merge "$1" --rebase --match-head-commit "$head_sha" 2>&1 >/dev/null); then
    exit 0
  fi
  if [ "$attempt" -ge "$attempts" ] || [[ $err != *"Base branch was modified"* ]]; then
    break
  fi
  sleep "$retry_seconds"
done

echo "$err" >&2
head -n 1 <<<"$err"
exit 1
