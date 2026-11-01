#!/usr/bin/env bash
# Tests that the github-actions entry in .github/dependabot.yml lists every
# directory that holds an action.yml, so the pins inside each action are
# updated.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
failures=0

directories=$(awk '
  /package-ecosystem:/ { in_entry = ($0 ~ /package-ecosystem: github-actions$/) }
  in_entry && /^[[:space:]]*directories:/ { print }
' .github/dependabot.yml)

for want in / $(git ls-files '*/action.yml' | xargs -n 1 dirname | sed 's|^|/|'); do
  if [[ "$directories" == *"\"$want\""* ]]; then
    echo "ok   covers $want"
  else
    echo "FAIL github-actions directories lack $want"
    failures=$((failures + 1))
  fi
done

exit $((failures > 0))
