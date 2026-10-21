#!/usr/bin/env bash
# Prints the Kiro prompt for a Dependabot PR: the fixed instructions in
# prompt.md followed by the metadata, PR body, and diff, each in its own tag.
# Every & in the inputs is escaped as &amp; and every < as &lt;, so no spelling
# of a closing tag, literal or entity-encoded, lets the text leave its tag.
#
# Usage: build-prompt.sh <metadata.json> <body.md> <diff.patch>
set -euo pipefail

max_body_bytes=65536
max_diff_bytes=204800
dir=$(dirname "$0")

escape() {
  sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' "$@"
}

body_bytes=$(wc -c < "$2" | tr -d ' ')
diff_bytes=$(wc -c < "$3" | tr -d ' ')

cat "$dir/prompt.md"
printf '\n<dependabot-metadata>\n'
escape "$1"
printf '\n</dependabot-metadata>\n\n<untrusted-pr-body>\n'
head -c "$max_body_bytes" "$2" | escape
if [ "$body_bytes" -gt "$max_body_bytes" ]; then
  printf '\n[body truncated: %s of %s bytes shown]' "$max_body_bytes" "$body_bytes"
fi
printf '\n</untrusted-pr-body>\n\n<untrusted-diff>\n'
head -c "$max_diff_bytes" "$3" | escape
if [ "$diff_bytes" -gt "$max_diff_bytes" ]; then
  printf '\n[diff truncated: %s of %s bytes shown]' "$max_diff_bytes" "$diff_bytes"
fi
printf '\n</untrusted-diff>\n'
