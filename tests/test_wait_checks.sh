#!/usr/bin/env bash
# Tests dependabot-review/wait-checks.sh with a fake gh that replays responses.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=$PWD/dependabot-review/wait-checks.sh
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
failures=0

# For `gh pr checks`, the fake gh prints line N of $FAKE_RESPONSES on its Nth
# call, repeating the last line once they run out, writes $FAKE_STDERR to
# stderr, and exits with $FAKE_EXIT. For `gh run list`, it does the same with
# $FAKE_RUNS, or prints [] without it.
cat > "$fixtures/gh" <<'GH'
#!/usr/bin/env bash
replay() {
  local n
  n=$(( $(cat "$2" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$2"
  total=$(wc -l < "$1")
  sed -n "$(( n < total ? n : total ))p" "$1"
}
if [ "$1 $2" = "run list" ]; then
  if [ -n "${FAKE_RUNS:-}" ]; then
    replay "$FAKE_RUNS" "$FAKE_COUNTER.runs"
  else
    echo '[]'
  fi
  exit 0
fi
replay "$FAKE_RESPONSES" "$FAKE_COUNTER"
if [ -n "${FAKE_STDERR:-}" ]; then
  printf '%s\n' "$FAKE_STDERR" >&2
fi
sleep "${FAKE_SLEEP:-0}"
exit "${FAKE_EXIT:-0}"
GH
chmod +x "$fixtures/gh"

c() {
  printf '[{"name":"lint","workflow":"Lint","bucket":"%s"}]' "$1"
}

# run <responses...>: runs the script against the responses with settings
# from the env, writing its stderr to $fixtures/stderr.
run() {
  printf '%s\n' "$@" > "$fixtures/responses"
  rm -f "$fixtures/counter" "$fixtures/counter.runs"
  PATH="$fixtures:$PATH" FAKE_RESPONSES="$fixtures/responses" \
    FAKE_COUNTER="$fixtures/counter" OWN_WORKFLOW="Dependabot Review" HEAD_SHA=abc123 \
    POLL_SECONDS=0 "$script" 1 2>"$fixtures/stderr"
}

# expect <name> <expected stdout> <responses...>; settings come from the env.
expect() {
  local name=$1 want=$2
  shift 2
  local got
  got=$(run "$@") || got=ERROR
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

# warns <name> <expected ::warning:: lines> <responses...>; settings come from
# the env.
warns() {
  local name=$1 want=$2
  shift 2
  run "$@" > /dev/null
  local got
  got=$(grep '^::warning::' "$fixtures/stderr")
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want '$want', got '$got'"
    failures=$((failures + 1))
  fi
}

FAKE_STDERR='HTTP 502: Bad Gateway' warns warns_with_gh_stderr \
  '::warning::gh pr checks did not list the checks: HTTP 502: Bad Gateway' "garbage" "$(c pass)"
FAKE_STDERR=$'first line\n100% done' warns escapes_the_warning \
  '::warning::gh pr checks did not list the checks: first line%0A100%25 done' "garbage" "$(c pass)"
FAKE_STDERR='HTTP 502: Bad Gateway' warns warns_once_per_message \
  '::warning::gh pr checks did not list the checks: HTTP 502: Bad Gateway' "garbage" "garbage" "garbage" "$(c pass)"
FAKE_STDERR='some checks are still pending' warns no_warning_for_a_list '' "$(c pending)" "$(c pass)"
warns no_warning_without_stderr '' "garbage" "$(c pass)"

r() {
  printf '[{"workflowName":"%s","status":"%s"},{"workflowName":"Dependabot Review","status":"in_progress"}]' "$1" "$2"
}
printf '%s\n' "$(r Test in_progress)" "$(r Test completed)" > "$fixtures/runs"
FAKE_RUNS="$fixtures/runs" expect waits_for_running_workflow pass "$(c pass)"
printf '%s\n' "$(r Test in_progress)" > "$fixtures/runs"
FAKE_RUNS="$fixtures/runs" TIMEOUT_SECONDS=0 expect running_workflow_times_out timeout "$(c pass)"

exit $((failures > 0))
