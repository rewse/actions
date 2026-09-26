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

exit $((failures > 0))
