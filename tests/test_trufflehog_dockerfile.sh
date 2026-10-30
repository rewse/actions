#!/usr/bin/env bash
# Tests that trufflehog/Dockerfile pins the TruffleHog image by tag and digest.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
dockerfile=trufflehog/Dockerfile
failures=0

lines=$(grep -Ev '^[[:space:]]*(#|$)' "$dockerfile" 2>/dev/null)

name=single_from_line
if [ -n "$lines" ] && [ "$(wc -l <<<"$lines")" -eq 1 ]; then
  echo "ok   $name"
else
  echo "FAIL $name: want one instruction in $dockerfile"
  failures=$((failures + 1))
fi

name=pins_tag_and_digest
if grep -Eq '^FROM ghcr\.io/trufflesecurity/trufflehog:[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$' <<<"$lines"; then
  echo "ok   $name"
else
  echo "FAIL $name: want FROM ghcr.io/trufflesecurity/trufflehog:<version>@sha256:<digest>"
  failures=$((failures + 1))
fi

exit $((failures > 0))
