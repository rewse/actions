#!/usr/bin/env bash
# Prints the Markdown review comment for a verdict. The first line is the
# marker that upsert-comment.sh looks for; HTML comments in the verdict and
# outcome are escaped so they cannot hide text or forge the marker.
#
# Usage: render-comment.sh <verdict.json> <head-sha> <outcome>
set -euo pipefail

jq -r --arg sha "$2" --arg outcome "$3" '
  def safe: gsub("<!--"; "&lt;!--");
  [
    "<!-- dependabot-kiro-review -->",
    "## Kiro risk review",
    "",
    "**Risk: \(.risk)**",
    "",
    (.summary | safe),
    "",
    (.reasons[] | "- \(safe)"),
    "",
    "Evaluated commit: \($sha)",
    "Outcome: \($outcome | safe)"
  ] | join("\n")
' "$1"
