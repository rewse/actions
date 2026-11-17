#!/usr/bin/env bash
# Tests the "Decide the tag" step of .github/workflows/trufflehog-auto-tag.yml
# against throwaway git repositories, with stub gate scripts in place of
# .github/scripts/next-auto-tag.sh.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
workflow=$PWD/.github/workflows/trufflehog-auto-tag.yml
failures=0
tmp=$(mktemp -d /tmp/trufflehog-auto-tag.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

# The run block of the step, without its YAML indentation.
step=$tmp/decide.sh
awk '
  /^[[:space:]]*- name: Decide the tag$/ { in_step = 1; next }
  in_step && /^[[:space:]]*- / { exit }
  in_step && /^[[:space:]]*run: \|$/ { in_run = 1; indent = -1; next }
  in_run {
    if ($0 ~ /^[[:space:]]*$/) { print ""; next }
    match($0, /^[[:space:]]*/)
    if (indent < 0) indent = RLENGTH
    if (RLENGTH < indent) exit
    print substr($0, indent + 1)
  }
' "$workflow" > "$step"
if [ ! -s "$step" ]; then
  echo "FAIL cannot find the run block of the Decide the tag step in $workflow"
  exit 1
fi

# new_repo <name>: creates a repository whose gate prints "from-<name>" and
# allows the tag.
new_repo() {
  repo=$tmp/$1
  git init -q -b main "$repo"
  git -C "$repo" config commit.gpgsign false
  git -C "$repo" config tag.gpgsign false
  # Keep global hooks, such as a secret scanner, out of throwaway commits.
  git -C "$repo" config core.hooksPath /dev/null
  set_gate "from-$1"
}

# set_gate <output>: commits a gate that prints the output and allows the tag.
set_gate() {
  mkdir -p "$repo/.github/scripts"
  printf '#!/usr/bin/env bash\necho %s\n' "$1" > "$repo/.github/scripts/next-auto-tag.sh"
  git -C "$repo" add .github/scripts/next-auto-tag.sh
  git -C "$repo" -c user.name='Repo Owner' -c user.email=owner@example.com commit -q -m "gate $1"
}

# expect <name> <output> <summary>: runs the step in the current repository
# and compares the step output and the step summary.
expect() {
  local name=$1 want_out=$2 want_summary=$3
  local run_dir got_out got_summary
  run_dir=$(mktemp -d "$tmp/run.XXXXXX")
  : > "$run_dir/output"
  : > "$run_dir/summary"
  (cd "$repo" && GITHUB_OUTPUT=$run_dir/output GITHUB_STEP_SUMMARY=$run_dir/summary \
    RUNNER_TEMP=$run_dir bash -e "$step") >/dev/null 2>&1
  got_out=$(cat "$run_dir/output")
  got_summary=$(cat "$run_dir/summary")
  if [ "$got_out" != "$want_out" ]; then
    echo "FAIL $name: want output '$want_out', got '$got_out'"
    failures=$((failures + 1))
  elif [ "$got_summary" != "$want_summary" ]; then
    echo "FAIL $name: want summary '$want_summary', got '$got_summary'"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

new_repo tagged
git -C "$repo" tag v1.0.0
set_gate from-head
expect runs_gate_of_latest_tag 'tag=from-tagged' ''

new_repo untagged
expect stops_without_release_tag '' 'Not tagged: no release tag'

new_repo other_tags_only
git -C "$repo" tag v1.0.0-rc.1
git -C "$repo" tag latest
expect stops_without_semver_tag '' 'Not tagged: no release tag'

new_repo tag_without_gate
git -C "$repo" rm -q .github/scripts/next-auto-tag.sh
git -C "$repo" -c user.name='Repo Owner' -c user.email=owner@example.com commit -q -m 'drop gate'
git -C "$repo" tag v1.0.0
set_gate from-head
expect stops_when_tag_lacks_gate '' 'Not tagged: v1.0.0 has no next-auto-tag.sh'

exit $((failures > 0))
