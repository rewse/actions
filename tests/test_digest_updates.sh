#!/usr/bin/env bash
# Tests dependabot-review/digest-updates.sh against fixed Dependabot metadata
# and PR diffs.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=dependabot-review/digest-updates.sh
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
failures=0

old=51e35c02a42cf2a6646c5879f5752b38098ed0a20056a989f0af3a3c5e697c9a
new=1cec10ad04e9e13d1107ae55c475ea3e8305871bd644fe39d7a926e91eaa3642
uv_old=af22a52f5eafef3d78e551599d405c02df61919d18028f0cea8eda93bc9986d0
uv_new=96f40d3904aad8d0bd010539001d36c8e2188b981e1334471a90c4a1d93bb490

major='"version-update:semver-major"'
patch='"version-update:semver-patch"'

# dep <name> <ecosystem> <prevVersion> <newVersion> <updateType JSON>
dep() {
  jq -cn --arg name "$1" --arg eco "$2" --arg prev "$3" --arg new "$4" \
    --argjson type "$5" \
    '{dependencyName: $name, packageEcosystem: $eco, prevVersion: $prev,
      newVersion: $new, updateType: $type}'
}

ubuntu=$(dep ubuntu/ubuntu docker "\`51e35c0\`" 26.04 "$major")
uv=$(dep astral-sh/uv docker 0.13.6 0.13.7 "$patch")

# file_diff <path> <removed line> <added line>
file_diff() {
  printf 'diff --git a/%s b/%s\nindex 1111111..2222222 100644\n--- a/%s\n+++ b/%s\n@@ -1,3 +1,3 @@\n-%s\n+%s\n \n' \
    "$1" "$1" "$1" "$1" "$2" "$3"
}

ubuntu_digest_diff=$(file_diff Dockerfile \
  "FROM public.ecr.aws/ubuntu/ubuntu:26.04@sha256:$old" \
  "FROM public.ecr.aws/ubuntu/ubuntu:26.04@sha256:$new")

# expect <name> <dependencyName> <want updateType> <json> <diff>
expect() {
  local name=$1 dep_name=$2 want=$3 json=$4
  local got
  printf '%s' "$5" > "$fixtures/diff.patch"
  got=$(UPDATED_DEPENDENCIES_JSON=$json "$script" "$fixtures/diff.patch" 2>/dev/null \
    | jq -r --arg name "$dep_name" '.[] | select(.dependencyName == $name) | .updateType')
  if [ "$got" = "$want" ]; then
    echo "ok   $name"
  else
    echo "FAIL $name: want $want, got '$got'"
    failures=$((failures + 1))
  fi
}

expect marks_digest_update ubuntu/ubuntu version-update:digest \
  "[$ubuntu]" "$ubuntu_digest_diff"

expect keeps_other_updates_in_group astral-sh/uv version-update:semver-patch \
  "[$uv,$ubuntu]" "$(file_diff Dockerfile \
    "FROM ghcr.io/astral-sh/uv:0.13.6@sha256:$uv_old AS uv" \
    "FROM ghcr.io/astral-sh/uv:0.13.7@sha256:$uv_new AS uv")
$ubuntu_digest_diff"

expect marks_digest_update_in_group ubuntu/ubuntu version-update:digest \
  "[$uv,$ubuntu]" "$(file_diff Dockerfile \
    "FROM ghcr.io/astral-sh/uv:0.13.6@sha256:$uv_old AS uv" \
    "FROM ghcr.io/astral-sh/uv:0.13.7@sha256:$uv_new AS uv")
$ubuntu_digest_diff"

expect marks_docker_hub_image node version-update:digest \
  "[$(dep node docker "\`51e35c0\`" 24 "$major")]" "$(file_diff Dockerfile \
    "FROM node:24@sha256:$old" "FROM node:24@sha256:$new")"

expect marks_registry_with_port ubuntu/ubuntu version-update:digest \
  "[$ubuntu]" "$(file_diff Dockerfile \
    "FROM localhost:5000/ubuntu/ubuntu:26.04@sha256:$old" \
    "FROM localhost:5000/ubuntu/ubuntu:26.04@sha256:$new")"

expect keeps_tag_change ubuntu/ubuntu version-update:semver-major \
  "[$ubuntu]" "$(file_diff Dockerfile \
    "FROM public.ecr.aws/ubuntu/ubuntu:26.04@sha256:$old" \
    "FROM public.ecr.aws/ubuntu/ubuntu:26.10@sha256:$new")"

expect keeps_version_as_previous ubuntu/ubuntu version-update:semver-major \
  "[$(dep ubuntu/ubuntu docker 24.04 26.04 "$major")]" "$ubuntu_digest_diff"

expect keeps_previous_digest_not_in_diff ubuntu/ubuntu version-update:semver-major \
  "[$(dep ubuntu/ubuntu docker "\`deadbee\`" 26.04 "$major")]" "$ubuntu_digest_diff"

expect keeps_other_ecosystem ubuntu/ubuntu version-update:semver-major \
  "[$(dep ubuntu/ubuntu npm "\`51e35c0\`" 26.04 "$major")]" "$ubuntu_digest_diff"

expect keeps_other_image_with_same_suffix ubuntu/ubuntu version-update:semver-major \
  "[$ubuntu]" "$(file_diff Dockerfile \
    "FROM public.ecr.aws/acme/ubuntu/ubuntu:26.04@sha256:$old" \
    "FROM public.ecr.aws/acme/ubuntu/ubuntu:26.04@sha256:$new")"

expect keeps_untagged_reference_change ubuntu/ubuntu version-update:semver-major \
  "[$ubuntu]" "$ubuntu_digest_diff
$(file_diff ci/Dockerfile \
    "FROM public.ecr.aws/ubuntu/ubuntu:26.04" \
    "FROM public.ecr.aws/ubuntu/ubuntu:26.10")"

expect keeps_tags_swapped_between_files ubuntu/ubuntu version-update:semver-major \
  "[$ubuntu]" "$(file_diff Dockerfile \
    "FROM public.ecr.aws/ubuntu/ubuntu:24.04@sha256:$old" \
    "FROM public.ecr.aws/ubuntu/ubuntu:26.04@sha256:$new")
$(file_diff ci/Dockerfile \
    "FROM public.ecr.aws/ubuntu/ubuntu:26.04@sha256:$old" \
    "FROM public.ecr.aws/ubuntu/ubuntu:24.04@sha256:$new")"

expect keeps_removed_reference_only ubuntu/ubuntu version-update:semver-major \
  "[$ubuntu]" "$(file_diff Dockerfile \
    "FROM public.ecr.aws/ubuntu/ubuntu:26.04@sha256:$old" \
    "FROM scratch")"

expect keeps_dropped_digest ubuntu/ubuntu version-update:semver-major \
  "[$ubuntu]" "$ubuntu_digest_diff
$(file_diff ci/Dockerfile \
    "FROM public.ecr.aws/ubuntu/ubuntu:26.04@sha256:$old" \
    "FROM public.ecr.aws/ubuntu/ubuntu:26.04")"

expect keeps_empty_previous_version ubuntu/ubuntu version-update:semver-major \
  "[$(dep ubuntu/ubuntu docker '' 26.04 "$major")]" "$ubuntu_digest_diff"

expect keeps_too_short_previous_digest ubuntu/ubuntu version-update:semver-major \
  "[$(dep ubuntu/ubuntu docker "\`51e35c\`" 26.04 "$major")]" "$ubuntu_digest_diff"

name=passes_invalid_json_through
printf '%s' "$ubuntu_digest_diff" > "$fixtures/diff.patch"
out=$(UPDATED_DEPENDENCIES_JSON='not json' "$script" "$fixtures/diff.patch" 2>/dev/null)
if [ "$out" = 'not json' ]; then
  echo "ok   $name"
else
  echo "FAIL $name: got '$out'"
  failures=$((failures + 1))
fi

name=passes_through_without_diff
out=$(UPDATED_DEPENDENCIES_JSON="[$ubuntu]" "$script" "$fixtures/missing.patch" 2>/dev/null \
  | jq -r '.[0].updateType')
if [ "$out" = version-update:semver-major ]; then
  echo "ok   $name"
else
  echo "FAIL $name: got '$out'"
  failures=$((failures + 1))
fi

exit $((failures > 0))
