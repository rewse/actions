#!/usr/bin/env bash
# Tests dependabot-review/parse-verdict.sh against fixed Kiro outputs.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=dependabot-review/parse-verdict.sh
failures=0

# expect <name> <expected stdout or FAIL> <Kiro output>
expect() {
  local name=$1 want=$2 input=$3
  local got
  if ! got=$("$script" <<<"$input" 2>/dev/null); then
    got=FAIL
  fi
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want, got $got"
    failures=$((failures + 1))
  fi
}

v='{"risk":"low","summary":"s","reasons":["r"]}'
h='{"risk":"high","summary":"t","reasons":[]}'

expect plain_line "$v" "$v"
expect takes_last_valid_line "$h" "$v"$'\n'"$h"
expect ignores_fenced_and_prose "$v" $'Here is my verdict:\n```json\n'"$v"$'\n```'
expect normalizes_key_order "$v" '{"reasons":["r"],"summary":"s","risk":"low"}'
expect rejects_unknown_risk FAIL '{"risk":"none","summary":"s","reasons":[]}'
expect rejects_non_string_reasons FAIL '{"risk":"low","summary":"s","reasons":[1]}'
expect rejects_missing_summary FAIL '{"risk":"low","reasons":[]}'
expect rejects_empty FAIL ''

exit $((failures > 0))
