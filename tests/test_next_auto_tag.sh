#!/usr/bin/env bash
# Tests .github/scripts/next-auto-tag.sh against throwaway git repositories, a
# fake curl that stands in for ghcr.io and the GitHub API, and a fake date.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=$PWD/.github/scripts/next-auto-tag.sh
failures=0
tmp=$(mktemp -d /tmp/next-auto-tag.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"

# digest_of <version>: the digest that the fake registry serves for a version.
digest_of() {
  printf 'sha256:%064d' "${1//./}"
}

# pin <version> [digest]: a Dockerfile line that pins the version, by default
# to the digest that the fake registry serves for it.
pin() {
  echo "FROM ghcr.io/trufflesecurity/trufflehog:$1@${2:-$(digest_of "$1")}"
}

# The fake curl hands out a token and answers manifest requests that carry it
# with digest_of <tag>, but only when the Accept header lists the Docker
# manifest list type, as ghcr.io serves the TruffleHog tags. It answers a
# GitHub Release lookup with FAKE_PUBLISHED_AT as published_at, or null when
# that is empty. FAKE_CURL_FAIL=token, manifest, or release makes that request
# fail.
cat > "$tmp/bin/curl" <<CURL
#!/usr/bin/env bash
$(declare -f digest_of)
CURL
cat >> "$tmp/bin/curl" <<'CURL'
args=" $* "
fail() {
  echo "curl: (22) The requested URL returned error: $1" >&2
  exit 22
}
case $args in
  *' --fail '*) ;;
  *) echo 'fake curl: missing --fail' >&2; exit 2 ;;
esac
case $args in
  *' https://ghcr.io/token?scope=repository:trufflesecurity/trufflehog:pull '*)
    [ "${FAKE_CURL_FAIL:-}" != token ] || fail 503
    echo '{"token":"fake-token"}'
    ;;
  *' https://ghcr.io/v2/trufflesecurity/trufflehog/manifests/'*)
    [ "${FAKE_CURL_FAIL:-}" != manifest ] || fail 503
    [[ $args == *'Authorization: Bearer fake-token'* ]] || fail 401
    tag=${args##*/manifests/}
    tag=${tag%% *}
    if [[ $args == *application/vnd.docker.distribution.manifest.list.v2+json* ]]; then
      digest=$(digest_of "$tag")
    else
      digest=sha256:$(printf '%064d' 1)
    fi
    printf 'HTTP/2 200\r\ncontent-type: application/vnd.docker.distribution.manifest.list.v2+json\r\ndocker-content-digest: %s\r\n\r\n' "$digest"
    ;;
  *' https://api.github.com/repos/trufflesecurity/trufflehog/releases/tags/v'*)
    [ "${FAKE_CURL_FAIL:-}" != release ] || fail 404
    tag=${args##*/releases/tags/}
    tag=${tag%% *}
    published=${FAKE_PUBLISHED_AT-2026-11-01T00:00:00Z}
    jq -cn --arg tag "$tag" --arg published "$published" \
      '{tag_name: $tag, published_at: (if $published == "" then null else $published end)}'
    ;;
  *) echo "fake curl: unexpected request: $*" >&2; exit 2 ;;
esac
CURL
chmod +x "$tmp/bin/curl"

# The fake date tells the time as FAKE_NOW, by default 2026-11-13T00:00:00Z.
cat > "$tmp/bin/date" <<'DATE'
#!/usr/bin/env bash
[ "$*" = +%s ] || { echo "fake date: unexpected arguments: $*" >&2; exit 2; }
echo "${FAKE_NOW:-1794528000}"
DATE
chmod +x "$tmp/bin/date"

bot_name='dependabot[bot]'
bot_email='49699333+dependabot[bot]@users.noreply.github.com'
# Numbers the TruffleHog versions that commit_as pins, so each one is newer.
serial=0

# new_repo <name>: creates a repository whose first commit, by a person, is
# tagged v1.1.5 and pins TruffleHog 3.99.<serial>, or $image when a test sets it.
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
      # A newer pinned image each time, or $image when a test sets it.
      serial=$((serial + 1))
      echo "${image:-$(pin "3.99.$serial")}" > "$repo/$path"
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
  if out=$(cd "$repo" && PATH="$tmp/bin:$PATH" "$script" 2>/dev/null); then
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

new_repo workflow_change
bot_commit trufflehog/Dockerfile .github/workflows/test.yml .github/dependabot.yml
expect allows_workflow_change tag v1.1.6

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

new_repo gate_script_change
bot_commit trufflehog/Dockerfile .github/scripts/next-auto-tag.sh
expect blocks_gate_script_change block 'Changed outside the allowed paths since v1.1.5: .github/scripts/next-auto-tag.sh'

new_repo other_github_paths
bot_commit trufflehog/Dockerfile .github/CODEOWNERS .github/actions/x/action.yml
expect blocks_other_github_paths block 'Changed outside the allowed paths since v1.1.5: .github/CODEOWNERS .github/actions/x/action.yml'

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

image=$(pin 3.99.5) new_repo downgrade
image=$(pin 3.99.4) bot_commit trufflehog/Dockerfile
expect blocks_downgrade block 'TruffleHog 3.99.4 in trufflehog/Dockerfile is not newer than 3.99.5 in v1.1.5'

image=$(pin 3.99.5) new_repo same_version
image=$(pin 3.99.5 "sha256:$(printf '%064d' 7)") bot_commit trufflehog/Dockerfile
expect blocks_same_version_new_digest block 'TruffleHog 3.99.5 in trufflehog/Dockerfile is not newer than 3.99.5 in v1.1.5'

image=$(pin 3.99.9) new_repo numeric_versions
image=$(pin 3.99.10) bot_commit trufflehog/Dockerfile
expect compares_versions_numerically tag v1.1.6

image=$(pin 3.9.5) new_repo minor_version
image=$(pin 3.10.0) bot_commit trufflehog/Dockerfile
expect allows_minor_update tag v1.1.6

image='FROM ghcr.io/trufflesecurity/trufflehog:latest' new_repo unpinned_at_tag
bot_commit trufflehog/Dockerfile
expect blocks_unpinned_image_at_tag block 'trufflehog/Dockerfile in v1.1.5 does not pin a ghcr.io/trufflesecurity/trufflehog version by digest'

image=$(pin 3.99.5) new_repo digest_mismatch
image=$(pin 3.99.6 "sha256:$(printf '%064d' 7)") bot_commit trufflehog/Dockerfile
expect blocks_digest_mismatch block "ghcr.io serves $(digest_of 3.99.6) for trufflehog:3.99.6, but trufflehog/Dockerfile pins sha256:$(printf '%064d' 7)"

new_repo registry_error
bot_commit trufflehog/Dockerfile
FAKE_CURL_FAIL=token expect blocks_token_error block "Could not get the digest of trufflehog:3.99.$serial from ghcr.io"
FAKE_CURL_FAIL=manifest expect blocks_registry_error block "Could not get the digest of trufflehog:3.99.$serial from ghcr.io"

new_repo release_age
bot_commit trufflehog/Dockerfile
FAKE_PUBLISHED_AT=2026-11-09T00:00:01Z expect blocks_recent_release block "TruffleHog 3.99.$serial was published at 2026-11-09T00:00:01Z, less than 96 hours ago"
FAKE_PUBLISHED_AT=2026-11-09T00:00:00Z expect allows_release_96_hours_old tag v1.1.6
FAKE_PUBLISHED_AT=2026-11-14T00:00:00Z expect blocks_future_release block "TruffleHog 3.99.$serial was published at 2026-11-14T00:00:00Z, less than 96 hours ago"
FAKE_CURL_FAIL=release expect blocks_release_lookup_error block "Could not get the publication time of TruffleHog 3.99.$serial from GitHub"
FAKE_PUBLISHED_AT='' expect blocks_unpublished_release block "Could not get the publication time of TruffleHog 3.99.$serial from GitHub"
FAKE_PUBLISHED_AT='2026-11-01 00:00:00' expect blocks_malformed_release_time block "Could not get the publication time of TruffleHog 3.99.$serial from GitHub"

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
out=$(cd "$repo" && PATH="$tmp/bin:$PATH" "$script" 2>/dev/null)
if [ "${#out}" -le 500 ] && [[ "$out" == "Changed outside the allowed paths since v1.1.5: "* ]]; then
  echo "ok   $name"
else
  echo "FAIL $name: reason has ${#out} characters"
  failures=$((failures + 1))
fi

exit $((failures > 0))
