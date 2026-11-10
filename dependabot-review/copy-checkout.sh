#!/usr/bin/env bash
# Copies the checkout <src> into the empty directory <dest>, leaving out the
# top-level .git and .kiro directories, and keeps symlinks as symlinks. Kiro
# runs in the copy because its search tools search only the working directory,
# and a .kiro there would add agents, hooks, and MCP servers, including an
# agent of the same name that replaces the one that limits its reads.
#
# Usage: copy-checkout.sh <src> <dest>
set -euo pipefail

if ! [ -d "$2" ] || [ -n "$(ls -A "$2")" ]; then
  echo "$2 is not an empty directory" >&2
  exit 1
fi
cp -RP "$1/." "$2/"
rm -rf "$2/.git" "$2/.kiro"
