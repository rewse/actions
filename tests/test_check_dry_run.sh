#!/usr/bin/env bash
# Tests dependabot-review/check-dry-run.sh against dry-run input values.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=dependabot-review/check-dry-run.sh
failures=0

# expect <name> <pass or fail> <dry-run value>
expect() {
  local name=$1 want=$2 value=$3
  local out got
  if out=$(DRY_RUN=$value "$script" 2>&1); then
    got=pass
  else
    got=fail
  fi
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: want $want, got $got"
    failures=$((failures + 1))
  elif [ "$got" = fail ] && [[ "$out" != *"::error::"*"dry-run"* ]]; then
    echo "FAIL $name: error '$out' does not name the dry-run input"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

expect accepts_true pass true
expect accepts_false pass false
expect rejects_yes fail yes
expect rejects_capitalized_true fail True
expect rejects_empty fail ""
expect rejects_padded_true fail " true"
expect rejects_trailing_newline fail $'true\n'

name=rejects_unset
if out=$(env -u DRY_RUN "$script" 2>&1); then
  echo "FAIL $name: want fail, got pass"
  failures=$((failures + 1))
else
  echo "ok   $name"
fi

exit $((failures > 0))
