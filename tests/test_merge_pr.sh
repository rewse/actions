#!/usr/bin/env bash
# Tests dependabot-review/merge-pr.sh with a fake gh that replays results.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=$PWD/dependabot-review/merge-pr.sh
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
failures=0

# On its Nth call, the fake gh appends its arguments to $FAKE_LOG, writes the
# Nth file of $FAKE_RESULTS (N.err) to stderr, and exits with the code in N.exit,
# repeating the last result once they run out.
cat > "$fixtures/gh" <<'GH'
#!/usr/bin/env bash
n=1
[ ! -f "$FAKE_LOG" ] || n=$(( $(wc -l < "$FAKE_LOG") + 1 ))
echo "$*" >> "$FAKE_LOG"
last=$(find "$FAKE_RESULTS" -name '*.exit' | wc -l | tr -d ' ')
[ "$n" -le "$last" ] || n=$last
cat "$FAKE_RESULTS/$n.err" >&2
exit "$(cat "$FAKE_RESULTS/$n.exit")"
GH
chmod +x "$fixtures/gh"

modified='GraphQL: Base branch was modified. Review and try the merge again. (mergePullRequest)'
head_moved='GraphQL: Head branch was modified. Review and try the merge again. (mergePullRequest)'

# run <exit>:<stderr>...: runs the script for PR 7 against the gh results,
# writing its stdout to $fixtures/stdout and its stderr to $fixtures/stderr,
# and prints its exit code.
run() {
  local i=0 result
  rm -rf "$fixtures/results" "$fixtures/log"
  mkdir "$fixtures/results"
  for result in "$@"; do
    i=$((i + 1))
    printf '%s' "${result%%:*}" > "$fixtures/results/$i.exit"
    printf '%s' "${result#*:}" > "$fixtures/results/$i.err"
  done
  PATH="$fixtures:$PATH" FAKE_RESULTS="$fixtures/results" FAKE_LOG="$fixtures/log" \
    HEAD_SHA=abc123 MERGE_RETRY_SECONDS=0 "$script" 7 \
    > "$fixtures/stdout" 2> "$fixtures/stderr"
  echo $?
}

calls() {
  wc -l < "$fixtures/log" | tr -d ' '
}

check() {
  if "$@"; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

name=merges_on_first_try
check [ "$(run 0:)" = 0 ]
check [ "$(cat "$fixtures/log")" = "pr merge 7 --rebase --match-head-commit abc123" ]
check [ ! -s "$fixtures/stdout" ]

name=retries_when_base_moved
check [ "$(run "1:$modified" 0:)" = 0 ]
check [ "$(calls)" = 2 ]
check [ ! -s "$fixtures/stdout" ]

name=gives_up_after_attempts
check [ "$(MERGE_ATTEMPTS=3 run "1:$modified")" = 1 ]
check [ "$(calls)" = 3 ]
check [ "$(cat "$fixtures/stdout")" = "$modified" ]

name=does_not_retry_when_head_moved
check [ "$(run "1:$head_moved" 0:)" = 1 ]
check [ "$(calls)" = 1 ]
check [ "$(cat "$fixtures/stdout")" = "$head_moved" ]

name=reports_first_line_and_full_error
check [ "$(run $'1:first line\nsecond line')" = 1 ]
check [ "$(cat "$fixtures/stdout")" = "first line" ]
check grep -qx "second line" "$fixtures/stderr"

name=requires_head_sha
PATH="$fixtures:$PATH" HEAD_SHA='' "$script" 7 > /dev/null 2>&1
check [ $? -ne 0 ]

exit $((failures > 0))
