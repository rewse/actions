#!/usr/bin/env bash
# Reads the Kiro CLI output on stdin and prints the last line that is a valid
# verdict, {"risk":"low|medium|high","summary":"...","reasons":["..."]}, as
# compact JSON. Exits 1 when no line qualifies, so the caller can fail closed.
set -euo pipefail

verdict=$(jq -R -c '
  fromjson?
  | select(type == "object")
  | select(.risk | IN("low", "medium", "high"))
  | select(.summary | type == "string")
  | select((.reasons | type == "array") and all(.reasons[]; type == "string"))
  | {risk, summary, reasons}
' | tail -n 1)

if [ -z "$verdict" ]; then
  echo "No valid verdict in the Kiro output" >&2
  exit 1
fi
echo "$verdict"
