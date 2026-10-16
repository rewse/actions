#!/usr/bin/env bash
# Posts a new review comment on a PR and prints its ID, or, given the ID of a
# comment from the same run, updates that comment. Each run gets its own
# comment so the PR keeps the history of earlier ratings.
#
# Usage: post-comment.sh <pr-number> <body-file> [comment-id]
set -euo pipefail

repo=${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}

if [ -n "${3:-}" ]; then
  gh api -X PATCH "repos/$repo/issues/comments/$3" -F "body=@$2" --jq .id
else
  gh api -X POST "repos/$repo/issues/$1/comments" -F "body=@$2" --jq .id
fi
