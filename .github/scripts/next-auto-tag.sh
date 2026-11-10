#!/usr/bin/env bash
# Prints the next patch tag when everything since the latest release tag is a
# Dependabot update of the TruffleHog image to a newer upstream release, plus
# Dependabot changes to paths that callers never run. Otherwise prints why not
# and exits 1.
set -euo pipefail

rev=${1:-HEAD}
dockerfile=trufflehog/Dockerfile
repository=trufflesecurity/trufflehog
bot='dependabot[bot] <49699333+dependabot[bot]@users.noreply.github.com>'
# The whole Dockerfile, capturing the version and the digest.
pin_re='^FROM ghcr\.io/trufflesecurity/trufflehog:([0-9]+\.[0-9]+\.[0-9]+)@(sha256:[0-9a-f]{64})$'

skip() {
  printf '%s\n' "${1:0:500}"
  exit 1
}

# Dependabot's github-actions updates touch the workflows and nothing else
# under .github/. The workflow runs this script from the latest release tag,
# so .github/scripts/ stays outside: an automatic release that changed the
# script would replace the gate for the next one.
allowed() {
  case $1 in
    "$dockerfile" | .pre-commit-config.yaml | .github/dependabot.yml | .github/workflows/* | tests/* | docs/*) return 0 ;;
    *) return 1 ;;
  esac
}

# newer <a> <b>: succeeds when version a is newer than version b.
newer() {
  local a b i
  IFS=. read -r -a a <<<"$1"
  IFS=. read -r -a b <<<"$2"
  for i in 0 1 2; do
    if [ "$((10#${a[i]}))" -ne "$((10#${b[i]}))" ]; then
      return "$((10#${a[i]} > 10#${b[i]} ? 0 : 1))"
    fi
  done
  return 1
}

# registry_digest <version>: prints the digest that ghcr.io serves for the
# version tag. The Accept header lists the index types first, so a
# multi-platform tag yields the index digest that Dependabot pins.
registry_digest() {
  local token headers
  token=$(curl --fail --silent --show-error --max-time 30 \
    "https://ghcr.io/token?scope=repository:$repository:pull" | jq -r '.token // empty') || return 1
  [ -n "$token" ] || return 1
  headers=$(curl --fail --silent --show-error --max-time 30 --head \
    -H "Authorization: Bearer $token" \
    -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json' \
    "https://ghcr.io/v2/$repository/manifests/$1") || return 1
  tr -d '\r' <<<"$headers" | awk 'tolower($1) == "docker-content-digest:" { print $2 }'
}

tag=$(git tag --merged "$rev" --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true)
[ -n "$tag" ] || skip 'No release tag found'

[ -n "$(git rev-list "$tag..$rev")" ] || skip "No commits since $tag"

# --no-renames lists both sides of a rename, so moving code out of an action
# directory cannot hide behind an allowed destination.
changed=$(git diff --name-only --no-renames "$tag" "$rev")
grep -Fxq "$dockerfile" <<<"$changed" || skip "$dockerfile did not change since $tag"

# Anyone who can push to main can forge git author metadata, so the image
# itself must be an upstream TruffleHog release: pinned by digest, newer than
# the one in the latest tag, and served by ghcr.io under that version tag.
from=$(git show "$rev:$dockerfile" 2>/dev/null || true)
[[ $from =~ $pin_re ]] ||
  skip "$dockerfile does not pin a ghcr.io/trufflesecurity/trufflehog version by digest"
version=${BASH_REMATCH[1]}
digest=${BASH_REMATCH[2]}

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

released=$(git show "$tag:$dockerfile" 2>/dev/null || true)
[[ $released =~ $pin_re ]] ||
  skip "$dockerfile in $tag does not pin a ghcr.io/trufflesecurity/trufflehog version by digest"
released_version=${BASH_REMATCH[1]}
newer "$version" "$released_version" ||
  skip "TruffleHog $version in $dockerfile is not newer than $released_version in $tag"

# The lookup fails closed: no answer from ghcr.io means no tag.
served=$(registry_digest "$version") && [ -n "$served" ] ||
  skip "Could not get the digest of trufflehog:$version from ghcr.io"
[ "$served" = "$digest" ] ||
  skip "ghcr.io serves $served for trufflehog:$version, but $dockerfile pins $digest"

IFS=. read -r major minor patch <<<"${tag#v}"
echo "v$major.$minor.$((patch + 1))"
