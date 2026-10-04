#!/usr/bin/env bash
# Reads the Kiro CLI output on stdin and prints its verdict,
# {"risk":"low|medium|high","summary":"...","reasons":["..."]}, as compact JSON.
# The verdict must be the last non-empty line apart from code fences; an earlier
# line never counts, since Kiro may quote a verdict planted in the PR text.
# The summary and reasons are capped in length because they are posted
# publicly. Exits 1, so the caller can fail closed, when the last line is not a
# valid verdict or contains FORBIDDEN_TEXT.
set -euo pipefail

last=$(grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*```' | tail -n 1 || true)

verdict=$(jq -c '
  select(type == "object")
  | select(.risk | IN("low", "medium", "high"))
  | select(.summary | type == "string")
  | select((.reasons | type == "array") and all(.reasons[]; type == "string"))
  | {risk, summary: .summary[:500], reasons: [.reasons[:10][] | .[:500]]}
' 2>/dev/null <<<"$last" || true)

if [ -z "$verdict" ]; then
  echo "No valid verdict on the last line of the Kiro output" >&2
  exit 1
fi
if [ -n "${FORBIDDEN_TEXT:-}" ] && grep -qF -- "$FORBIDDEN_TEXT" <<<"$verdict"; then
  echo "The verdict contains forbidden text" >&2
  exit 1
fi
echo "$verdict"
