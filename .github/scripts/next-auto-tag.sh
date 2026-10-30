#!/usr/bin/env bash
# Prints the next patch tag when everything since the latest release tag is a
# Dependabot update of the TruffleHog image, plus Dependabot changes to paths
# that callers never run. Otherwise prints why not and exits 1.
set -euo pipefail

rev=${1:-HEAD}
dockerfile=trufflehog/Dockerfile
bot='dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>'

skip() {
  printf '%s\n' "${1:0:500}"
  exit 1
}

allowed() {
  case $1 in
    "$dockerfile" | .pre-commit-config.yaml | .github/* | tests/* | docs/*) return 0 ;;
    *) return 1 ;;
  esac
}

tag=$(git tag --merged "$rev" --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
[ -n "$tag" ] || skip 'No release tag found'

[ -n "$(git rev-list "$tag..$rev")" ] || skip "No commits since $tag"

# --no-renames lists both sides of a rename, so moving code out of an action
# directory cannot hide behind an allowed destination.
changed=$(git diff --name-only --no-renames "$tag" "$rev")
grep -Fxq "$dockerfile" <<<"$changed" || skip "$dockerfile did not change since $tag"

# The author check trusts git metadata, so the image itself must still be an
# upstream TruffleHog release pinned by digest.
from=$(git show "$rev:$dockerfile" 2>/dev/null || true)
grep -Eqx 'FROM ghcr\.io/trufflesecurity/trufflehog:[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' <<<"$from" && [ "$(wc -l <<<"$from")" -eq 1 ] ||
  skip "$dockerfile does not pin a ghcr.io/trufflesecurity/trufflehog version by digest"

outside=()
while IFS= read -r path; do
  allowed "$path" || outside+=("$path")
done <<<"$changed"
[ "${#outside[@]}" -eq 0 ] || skip "Changed outside the allowed paths since $tag: ${outside[*]}"

others=()
while IFS=' ' read -r sha author; do
  [ "$author" = "$bot" ] || others+=("$sha")
done < <(git log --format='%h %an <%ae>' "$tag..$rev")
[ "${#others[@]}" -eq 0 ] || skip "Commits by someone other than Dependabot since $tag: ${others[*]}"

IFS=. read -r major minor patch <<<"${tag#v}"
echo "v$major.$minor.$((patch + 1))"
