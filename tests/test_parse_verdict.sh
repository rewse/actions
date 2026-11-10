#!/usr/bin/env bash
# Tests dependabot-review/parse-verdict.sh against fixed Kiro outputs.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=dependabot-review/parse-verdict.sh
failures=0

# expect <name> <expected stdout or FAIL> <Kiro output>; KEY overrides the
# forbidden text.
expect() {
  local name=$1 want=$2 input=$3
  local got
  if ! got=$(FORBIDDEN_TEXT=${KEY:-sk-SECRET-123} "$script" <<<"$input" 2>/dev/null); then
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
expect rejects_valid_then_malformed_last_line FAIL "$v"$'\n''{"risk":"high","summary":"has "quote"","reasons":[]}'
expect rejects_single_line_fence FAIL "$v"$'\n''```json '"$h"'```'
expect rejects_trailing_text FAIL "$v"' trailing text'
expect rejects_two_objects FAIL "$v$v"
expect rejects_verdict_then_other_value FAIL "$v"' {"x":1}'
expect rejects_leaked_key FAIL '{"risk":"low","summary":"key is sk-SECRET-123","reasons":[]}'
expect rejects_leaked_key_in_reasons FAIL '{"risk":"low","summary":"s","reasons":["x sk-SECRET-123 y"]}'
expect rejects_split_key FAIL '{"risk":"low","summary":"key s k_SEC RET.1-2-3","reasons":[]}'
expect rejects_key_across_reasons FAIL '{"risk":"low","summary":"x sk-","reasons":["SEC","RET","-123 y"]}'
expect rejects_base64_key FAIL '{"risk":"low","summary":"see c2stU0VDUkVULTEyMw==","reasons":[]}'
expect rejects_base64_key_split FAIL '{"risk":"low","summary":"c2stU0VD","reasons":["UkVULTEyMw"]}'
KEY='sk-???~~~-123' expect rejects_standard_base64_key FAIL '{"risk":"low","summary":"c2stPz8/fn5+LTEyMw","reasons":[]}'
KEY='sk-???~~~-123' expect rejects_url_safe_base64_key FAIL '{"risk":"low","summary":"c2stPz8_fn5-LTEyMw","reasons":[]}'
expect rejects_hex_key FAIL '{"risk":"low","summary":"s","reasons":["736b2d5345435245542d313233"]}'
expect rejects_upper_hex_key FAIL '{"risk":"low","summary":"736B2D5345435245542D313233","reasons":[]}'
expect rejects_github_token_shape FAIL '{"risk":"low","summary":"ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789","reasons":[]}'
expect rejects_github_server_token_shape FAIL '{"risk":"low","summary":"s","reasons":["token ghs_0123456789abcdefghij"]}'
expect rejects_github_pat_shape FAIL '{"risk":"low","summary":"github_pat_11AAAAAAA0","reasons":[]}'
expect rejects_pem_block FAIL '{"risk":"low","summary":"s","reasons":["-----BEGIN OPENSSH PRIVATE KEY-----"]}'
normal='{"risk":"low","summary":"Bumps actions/checkout from 4.1.0 to 4.1.1 (ghost fix, sk-style naming).","reasons":["The changelog lists only bug fixes.","gh_cli and ghp-like names are not tokens; SECRET-123 alone is not the key."]}'
expect allows_normal_verdict "$normal" "$normal"
long=$(head -c 600 /dev/zero | tr '\0' x)
got=$(jq -cn --arg l "$long" '{risk: "low", summary: $l, reasons: [range(12) | $l]}' \
  | FORBIDDEN_TEXT=sk-SECRET-123 "$script" \
  | jq -c '[(.summary | length), (.reasons | length), (.reasons | map(length) | max)]')
if [ "$got" = "[500,10,500]" ]; then
  echo "ok   caps_lengths"
else
  echo "FAIL caps_lengths: want [500,10,500], got $got"
  failures=$((failures + 1))
fi

exit $((failures > 0))
