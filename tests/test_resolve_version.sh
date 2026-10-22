#!/usr/bin/env bash
# Tests setup-safe-chain/resolve-version.sh against fixed release lists.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=setup-safe-chain/resolve-version.sh
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
failures=0

release() {
  printf '{"tag_name":"%s","published_at":"%s","draft":%s,"prerelease":%s,"immutable":%s}' "$@"
}

# expect <name> <expected stdout or FAIL> <cooldown hours> <releases...>
expect() {
  local name=$1 want=$2 hours=$3
  shift 3
  local file="$fixtures/$name.json"
  (IFS=,; printf '[%s]' "$*") > "$file"
  local got
  if got=$(COOLDOWN_HOURS=$hours SAFE_CHAIN_RELEASES_FILE=$file "$script" 2>/dev/null); then
    :
  else
    got=FAIL
  fi
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want, got $got"
    failures=$((failures + 1))
  fi
}

old=2000-01-01T00:00:00Z
older=1999-01-01T00:00:00Z
new=2999-01-01T00:00:00Z

expect picks_newest_aged 1.0.1 96 \
  "$(release 1.0.2 $new false false true)" \
  "$(release 1.0.1 $old false false true)" \
  "$(release 1.0.0 $older false false true)"
expect skips_mutable 1.0.0 96 \
  "$(release 1.0.1 $old false false false)" \
  "$(release 1.0.0 $old false false true)"
expect skips_draft_and_prerelease 1.0.0 96 \
  "$(release 1.0.2 $old true false true)" \
  "$(release 1.0.1 $old false true true)" \
  "$(release 1.0.0 $old false false true)"
expect fails_without_aged_release FAIL 96 \
  "$(release 1.0.0 $new false false true)"
expect fails_on_empty_list FAIL 96
expect rejects_non_numeric_cooldown FAIL abc \
  "$(release 1.0.0 $old false false true)"

# For `gh api`, the fake gh prints line N of $FAKE_RESPONSES on its Nth call,
# repeating the last line once they run out.
cat > "$fixtures/gh" <<'GH'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE_COUNTER" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FAKE_COUNTER"
total=$(wc -l < "$FAKE_RESPONSES")
sed -n "$(( n < total ? n : total ))p" "$FAKE_RESPONSES"
GH
chmod +x "$fixtures/gh"

# expect_api <name> <expected stdout or FAIL> <expected calls> <responses...>
expect_api() {
  local name=$1 want=$2 calls=$3
  shift 3
  printf '%s\n' "$@" > "$fixtures/responses"
  rm -f "$fixtures/counter"
  local got
  if got=$(PATH="$fixtures:$PATH" FAKE_RESPONSES="$fixtures/responses" \
    FAKE_COUNTER="$fixtures/counter" COOLDOWN_HOURS=96 RETRY_SECONDS=0 \
    "$script" 2>/dev/null); then
    :
  else
    got=FAIL
  fi
  local made
  made=$(cat "$fixtures/counter")
  if [ "$got" = "$want" ] && [ "$made" = "$calls" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want after $calls calls, got $got after $made"
    failures=$((failures + 1))
  fi
}

aged="[$(release 1.0.0 $old false false true)]"
expect_api uses_first_nonempty_response 1.0.0 1 "$aged"
expect_api retries_empty_response 1.0.0 3 '[]' '[]' "$aged"
expect_api fails_after_repeated_empty_responses FAIL 5 '[]'

exit $((failures > 0))
