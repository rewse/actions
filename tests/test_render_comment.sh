#!/usr/bin/env bash
# Tests dependabot-review/render-comment.sh against fixed verdicts.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=dependabot-review/render-comment.sh
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
failures=0

check() {
  if "$@"; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

render() {
  printf '%s' "$1" > "$fixtures/verdict.json"
  "$script" "$fixtures/verdict.json" abc123 "$2"
}

out=$(render '{"risk":"low","summary":"Patch bump.","reasons":["a","b"]}' "Merged with rebase.")

name=starts_with_marker
check [ "$(head -n 1 <<<"$out")" = '<!-- dependabot-kiro-review -->' ]
check grep -qxF '**Risk: low**' <<<"$out"
check grep -qxF 'Patch bump.' <<<"$out"

name=lists_reasons
check grep -qxF -- '- a' <<<"$out"
check grep -qxF -- '- b' <<<"$out"

name=includes_sha_and_outcome
check grep -qF 'Evaluated commit: abc123' <<<"$out"
check grep -qF 'Outcome: Merged with rebase.' <<<"$out"

name=neutralizes_marker_in_summary
out=$(render '{"risk":"high","summary":"<!-- dependabot-kiro-review -->","reasons":["<!-- x -->"]}' "Merge failed: <!-- y -->")
check [ "$(grep -cF '<!--' <<<"$out")" = 1 ]

exit $((failures > 0))
