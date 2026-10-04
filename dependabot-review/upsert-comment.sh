#!/usr/bin/env bash
# Creates the review comment on a PR, or updates the one this action posted
# before, found by the marker on its first line.
#
# Usage: upsert-comment.sh <pr-number> <body-file>
set -euo pipefail

marker='<!-- dependabot-kiro-review -->'
repo=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}

id=$(gh api "repos/$repo/issues/$1/comments" --paginate --jq "
  .[] | select(.user.login == \"github-actions[bot]\" and (.body | startswith(\"$marker\"))) | .id
" | head -n 1)

if [ -n "$id" ]; then
  gh api -X PATCH "repos/$repo/issues/comments/$id" -F "body=@$2" >/dev/null
else
  gh api -X POST "repos/$repo/issues/$1/comments" -F "body=@$2" >/dev/null
fi
