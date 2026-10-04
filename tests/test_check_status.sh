#!/usr/bin/env bash
# Tests dependabot-review/check-status.sh against fixed gh pr checks output.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=dependabot-review/check-status.sh
failures=0

c() {
  printf '{"name":"%s","workflow":"%s","bucket":"%s"}' "$@"
}

# expect <name> <expected stdout> <gh pr checks JSON>
expect() {
  local name=$1 want=$2 input=$3
  local got
  got=$(OWN_WORKFLOW="Dependabot Review" "$script" <<<"$input" 2>/dev/null) || got=ERROR
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want, got $got"
    failures=$((failures + 1))
  fi
}

expect excludes_own none "[$(c Review 'Dependabot Review' pending)]"
expect all_pass pass "[$(c lint Lint pass),$(c t Test skipping),$(c Review 'Dependabot Review' pending)]"
expect any_pending pending "[$(c lint Lint pass),$(c t Test pending)]"
expect fail_wins_over_pending fail "[$(c lint Lint fail),$(c t Test pending)]"
expect cancel_counts_as_fail fail "[$(c lint Lint cancel)]"
expect empty_is_none none "[]"

exit $((failures > 0))
