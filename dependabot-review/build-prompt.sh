#!/usr/bin/env bash
# Prints the Kiro prompt for a Dependabot PR: the fixed instructions in
# prompt.md followed by the metadata, PR body, and diff, each in its own tag.
# Closing tags inside the inputs are escaped so the text cannot leave its tag.
#
# Usage: build-prompt.sh <metadata.json> <body.md> <diff.patch>
set -euo pipefail

max_diff_bytes=204800
dir=$(dirname "$0")

escape() {
  sed -e 's#</untrusted-#<\\/untrusted-#g' -e 's#</dependabot-metadata#<\\/dependabot-metadata#g' "$@"
}

diff_bytes=$(wc -c < "$3" | tr -d ' ')

cat "$dir/prompt.md"
printf '\n<dependabot-metadata>\n'
escape "$1"
printf '\n</dependabot-metadata>\n\n<untrusted-pr-body>\n'
escape "$2"
printf '\n</untrusted-pr-body>\n\n<untrusted-diff>\n'
head -c "$max_diff_bytes" "$3" | escape
if [ "$diff_bytes" -gt "$max_diff_bytes" ]; then
  printf '\n[diff truncated: %s of %s bytes shown]' "$max_diff_bytes" "$diff_bytes"
fi
printf '\n</untrusted-diff>\n'
