#!/usr/bin/env bash
# Prints the Kiro agent for the risk rating: kiro-agent.json with $REPO_DIR and
# $INPUT_DIR replaced by the given directories as physical absolute paths, so
# its file tools can read those two directories and nothing else. The allow
# rule lets Kiro read them without asking, and the deny rule refuses fs_read
# everywhere else; in Kiro's V3 engine a deny wins over every other grant,
# including --trust-tools, and Kiro checks a symlink against its target.
#
# Usage: render-kiro-agent.sh <repo-dir> <input-dir>
set -euo pipefail

dir=$(dirname "$0")

# resolve <dir>: prints the physical path of an existing directory other than
# /, refusing glob characters, which the permission rules read as patterns.
resolve() {
  local path
  path=$(cd "$1" && pwd -P) || return 1
  case $path in
    / | *[][*?{}\\]*)
      echo "Cannot scope Kiro's reads to $path" >&2
      return 1
      ;;
  esac
  printf '%s\n' "$path"
}

repo=$(resolve "$1")
input=$(resolve "$2")
jq --arg repo "$repo" --arg input "$input" \
  'walk(if . == "$REPO_DIR" then $repo elif . == "$INPUT_DIR" then $input else . end)' \
  "$dir/kiro-agent.json"
