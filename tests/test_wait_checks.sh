#!/usr/bin/env bash
# Tests dependabot-review/wait-checks.sh with a fake gh that replays responses.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=$PWD/dependabot-review/wait-checks.sh
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
failures=0

# The fake gh prints line N of $FAKE_RESPONSES on its Nth call, repeating the
# last line once they run out, and exits with $FAKE_EXIT.
cat > "$fixtures/gh" <<'GH'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE_COUNTER" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$FAKE_COUNTER"
total=$(wc -l < "$FAKE_RESPONSES")
sed -n "$(( n < total ? n : total ))p" "$FAKE_RESPONSES"
sleep "${FAKE_SLEEP:-0}"
exit "${FAKE_EXIT:-0}"
GH
chmod +x "$fixtures/gh"

c() {
  printf '[{"name":"lint","workflow":"Lint","bucket":"%s"}]' "$1"
}

# expect <name> <expected stdout> <responses...>; settings come from the env.
expect() {
  local name=$1 want=$2
  shift 2
  printf '%s\n' "$@" > "$fixtures/responses"
  rm -f "$fixtures/counter"
  local got
  got=$(PATH="$fixtures:$PATH" FAKE_RESPONSES="$fixtures/responses" \
    FAKE_COUNTER="$fixtures/counter" OWN_WORKFLOW="Dependabot Review" \
    POLL_SECONDS=0 "$script" 1 2>/dev/null) || got=ERROR
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want, got $got"
    failures=$((failures + 1))
  fi
}

expect returns_pass_after_pending pass "$(c pending)" "$(c pass)"
expect returns_fail fail "$(c fail)"
NONE_GRACE_SECONDS=5 expect none_is_pending_during_grace pass "[]" "$(c pass)"
NONE_GRACE_SECONDS=0 expect none_after_grace none "[]"
FAKE_SLEEP=1 TIMEOUT_SECONDS=1 expect times_out timeout "$(c pending)"
FAKE_EXIT=8 expect tolerates_gh_exit_codes pass "$(c pending)" "$(c pass)"
expect treats_garbage_as_none pass "no checks reported" "$(c pass)"

exit $((failures > 0))
