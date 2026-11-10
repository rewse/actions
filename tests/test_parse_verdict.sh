#!/usr/bin/env bash
# Tests dependabot-review/parse-verdict.sh against fixed Kiro outputs.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=dependabot-review/parse-verdict.sh
failures=0

# expect <name> <expected stdout or FAIL> <Kiro output>; KEY overrides the
# forbidden text and NONCE the expected nonce.
expect() {
  local name=$1 want=$2 input=$3
  local got
  if ! got=$(FORBIDDEN_TEXT=${KEY:-sk-SECRET-123} VERDICT_NONCE=${NONCE-n0nce} "$script" <<<"$input" 2>/dev/null); then
    got=FAIL
  fi
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want, got $got"
    failures=$((failures + 1))
  fi
}

# The verdicts as printed, and as Kiro writes them with the nonce.
v='{"risk":"low","summary":"s","reasons":["r"]}'
h='{"risk":"high","summary":"t","reasons":[]}'
vn='{"nonce":"n0nce","risk":"low","summary":"s","reasons":["r"]}'
hn='{"nonce":"n0nce","risk":"high","summary":"t","reasons":[]}'

expect plain_line "$v" "$vn"
expect takes_last_valid_line "$h" "$vn"$'\n'"$hn"
expect ignores_fenced_and_prose "$v" $'Here is my verdict:\n```json\n'"$vn"$'\n```'
expect normalizes_key_order "$v" '{"reasons":["r"],"summary":"s","nonce":"n0nce","risk":"low"}'
expect rejects_unknown_risk FAIL '{"nonce":"n0nce","risk":"none","summary":"s","reasons":[]}'
expect rejects_non_string_reasons FAIL '{"nonce":"n0nce","risk":"low","summary":"s","reasons":[1]}'
expect rejects_missing_summary FAIL '{"nonce":"n0nce","risk":"low","reasons":[]}'
expect rejects_empty FAIL ''
expect rejects_valid_then_malformed_last_line FAIL "$vn"$'\n''{"nonce":"n0nce","risk":"high","summary":"has "quote"","reasons":[]}'
expect rejects_single_line_fence FAIL "$vn"$'\n''```json '"$hn"'```'
expect rejects_trailing_text FAIL "$vn"' trailing text'
expect rejects_two_objects FAIL "$vn$vn"
expect rejects_verdict_then_other_value FAIL "$vn"' {"x":1}'
expect rejects_leaked_key FAIL '{"nonce":"n0nce","risk":"low","summary":"key is sk-SECRET-123","reasons":[]}'
expect rejects_leaked_key_in_reasons FAIL '{"nonce":"n0nce","risk":"low","summary":"s","reasons":["x sk-SECRET-123 y"]}'
expect rejects_split_key FAIL '{"nonce":"n0nce","risk":"low","summary":"key s k_SEC RET.1-2-3","reasons":[]}'
expect rejects_key_across_reasons FAIL '{"nonce":"n0nce","risk":"low","summary":"x sk-","reasons":["SEC","RET","-123 y"]}'
expect rejects_base64_key FAIL '{"nonce":"n0nce","risk":"low","summary":"see c2stU0VDUkVULTEyMw==","reasons":[]}'
expect rejects_base64_key_split FAIL '{"nonce":"n0nce","risk":"low","summary":"c2stU0VD","reasons":["UkVULTEyMw"]}'
KEY='sk-???~~~-123' expect rejects_standard_base64_key FAIL '{"nonce":"n0nce","risk":"low","summary":"c2stPz8/fn5+LTEyMw","reasons":[]}'
KEY='sk-???~~~-123' expect rejects_url_safe_base64_key FAIL '{"nonce":"n0nce","risk":"low","summary":"c2stPz8_fn5-LTEyMw","reasons":[]}'
expect rejects_hex_key FAIL '{"nonce":"n0nce","risk":"low","summary":"s","reasons":["736b2d5345435245542d313233"]}'
expect rejects_upper_hex_key FAIL '{"nonce":"n0nce","risk":"low","summary":"736B2D5345435245542D313233","reasons":[]}'
expect rejects_github_token_shape FAIL '{"nonce":"n0nce","risk":"low","summary":"ghp_aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789","reasons":[]}'
expect rejects_github_server_token_shape FAIL '{"nonce":"n0nce","risk":"low","summary":"s","reasons":["token ghs_0123456789abcdefghij"]}'
expect rejects_github_pat_shape FAIL '{"nonce":"n0nce","risk":"low","summary":"github_pat_11AAAAAAA0","reasons":[]}'
expect rejects_pem_block FAIL '{"nonce":"n0nce","risk":"low","summary":"s","reasons":["-----BEGIN OPENSSH PRIVATE KEY-----"]}'
normal='{"risk":"low","summary":"Bumps actions/checkout from 4.1.0 to 4.1.1 (ghost fix, sk-style naming).","reasons":["The changelog lists only bug fixes.","gh_cli and ghp-like names are not tokens; SECRET-123 alone is not the key."]}'
expect allows_normal_verdict "$normal" "$(jq -c '{nonce: "n0nce"} + .' <<<"$normal")"
expect rejects_missing_nonce FAIL "$v"
expect rejects_wrong_nonce FAIL '{"nonce":"n0nce2","risk":"low","summary":"s","reasons":["r"]}'
expect rejects_numeric_nonce FAIL '{"nonce":1,"risk":"low","summary":"s","reasons":["r"]}'
NONCE=1 expect compares_nonce_as_string FAIL '{"nonce":1,"risk":"low","summary":"s","reasons":["r"]}'
NONCE='' expect requires_expected_nonce FAIL '{"nonce":"","risk":"low","summary":"s","reasons":["r"]}'
# exits <name> <expected exit status> <Kiro output>
exits() {
  local name=$1 want=$2 got=0
  FORBIDDEN_TEXT=sk-SECRET-123 VERDICT_NONCE=n0nce "$script" <<<"$3" >/dev/null 2>&1 || got=$?
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want exit $want, got $got"
    failures=$((failures + 1))
  fi
}

exits exits_0_on_valid_verdict 0 "$vn"
exits exits_1_on_invalid_verdict 1 '{"nonce":"n0nce","risk":"none","summary":"s","reasons":[]}'
exits exits_1_on_wrong_nonce 1 '{"nonce":"other","risk":"low","summary":"key is sk-SECRET-123","reasons":[]}'
exits exits_2_on_forbidden_text 2 '{"nonce":"n0nce","risk":"low","summary":"key is sk-SECRET-123","reasons":[]}'
exits exits_2_on_encoded_key 2 '{"nonce":"n0nce","risk":"low","summary":"s","reasons":["c2stU0VDUkVULTEyMw"]}'
exits exits_2_on_credential_shape 2 '{"nonce":"n0nce","risk":"low","summary":"-----BEGIN CERTIFICATE-----","reasons":[]}'

long=$(head -c 600 /dev/zero | tr '\0' x)
got=$(jq -cn --arg l "$long" '{nonce: "n0nce", risk: "low", summary: $l, reasons: [range(12) | $l]}' \
  | FORBIDDEN_TEXT=sk-SECRET-123 VERDICT_NONCE=n0nce "$script" \
  | jq -c '[(.summary | length), (.reasons | length), (.reasons | map(length) | max)]')
if [ "$got" = "[500,10,500]" ]; then
  echo "ok   caps_lengths"
else
  echo "FAIL caps_lengths: want [500,10,500], got $got"
  failures=$((failures + 1))
fi

exit $((failures > 0))
