#!/usr/bin/env bash
# Reads `gh pr checks --json name,workflow,bucket` on stdin and prints the
# combined state of every check outside OWN_WORKFLOW: none, fail, pending, or
# pass. A cancelled check counts as a failure.
set -euo pipefail

jq -r --arg own "${OWN_WORKFLOW:?OWN_WORKFLOW must be set}" '
  [.[] | select(.workflow != $own) | .bucket] as $buckets
  | if ($buckets | length) == 0 then "none"
    elif any($buckets[]; IN("fail", "cancel")) then "fail"
    elif any($buckets[]; . == "pending") then "pending"
    else "pass"
    end
'
