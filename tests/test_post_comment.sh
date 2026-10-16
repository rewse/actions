#!/usr/bin/env bash
# Tests dependabot-review/post-comment.sh with a fake gh that records its
# arguments.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=$PWD/dependabot-review/post-comment.sh
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
failures=0

# The fake gh writes its arguments to $FAKE_ARGS and prints the comment ID
# that `--jq .id` would extract.
cat > "$fixtures/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FAKE_ARGS"
echo 42
GH
chmod +x "$fixtures/gh"

check() {
  if "$@"; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

run() {
  PATH="$fixtures:$PATH" FAKE_ARGS="$fixtures/args" GITHUB_REPOSITORY=owner/repo \
    "$script" "$@"
}

echo body > "$fixtures/body.md"

name=posts_new_comment_without_id
out=$(run 7 "$fixtures/body.md")
check grep -qxF POST "$fixtures/args"
check grep -qxF repos/owner/repo/issues/7/comments "$fixtures/args"
check [ "$out" = 42 ]

name=updates_given_comment
out=$(run 7 "$fixtures/body.md" 99)
check grep -qxF PATCH "$fixtures/args"
check grep -qxF repos/owner/repo/issues/comments/99 "$fixtures/args"
check [ "$out" = 42 ]

name=empty_id_posts_new_comment
run 7 "$fixtures/body.md" "" > /dev/null
check grep -qxF POST "$fixtures/args"

exit $((failures > 0))
