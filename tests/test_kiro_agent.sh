#!/usr/bin/env bash
# Tests dependabot-review/render-kiro-agent.sh, copy-checkout.sh, and the flags
# that action.yml runs Kiro with.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
script=$PWD/dependabot-review/render-kiro-agent.sh
copy=$PWD/dependabot-review/copy-checkout.sh
fixtures=$(mktemp -d)
trap 'rm -rf "$fixtures"' EXIT
failures=0

check() {
  if "$@"; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    failures=$((failures + 1))
  fi
}

# refuses <command>...: checks that the command fails and prints nothing on
# stdout.
refuses() {
  local out
  if out=$("$@" 2>/dev/null) || [ -n "$out" ]; then
    echo "FAIL $name"
    failures=$((failures + 1))
  else
    echo "ok   $name"
  fi
}

# rendered <jq filter>: prints the filter applied to the agent rendered for
# $repo and $input.
rendered() {
  "$script" "$repo" "$input" 2>/dev/null | jq -c "$1"
}

real=$(cd "$fixtures" && pwd -P)
mkdir -p "$fixtures/repo" "$fixtures/input" "$fixtures/glob*dir" "$fixtures/brace{dir}"
ln -s "$real/repo" "$fixtures/repo-link"
repo=$fixtures/repo
input=$fixtures/input

name=names_the_agent
check [ "$(rendered .name)" = '"dependabot-review"' ]

name=lists_only_read_tools
check [ "$(rendered .tools)" = '["read_file","list_directory","file_search","grep_search"]' ]

name=adds_no_mcp_servers
check [ "$(rendered '[.includeMcpJson, .mcpServers]')" = '[false,null]' ]

name=sets_only_rules
check [ "$(rendered '.permissions | keys')" = '["rules"]' ]

name=rules_cover_only_fs_read
check [ "$(rendered '[.permissions.rules[].capability] | unique')" = '["fs_read"]' ]

name=allows_repo_and_input
want=$(jq -cn --arg r "$real/repo" --arg i "$real/input" '[{capability: "fs_read", match: [$r, $i], effect: "allow"}]')
check [ "$(rendered '[.permissions.rules[] | select(.effect == "allow")]')" = "$want" ]

name=denies_everything_else
want=$(jq -cn --arg r "$real/repo" --arg i "$real/input" '[{capability: "fs_read", match: ["/"], exclude: [$r, $i], effect: "deny"}]')
check [ "$(rendered '[.permissions.rules[] | select(.effect == "deny")]')" = "$want" ]

name=leaves_no_placeholder
check [ "$("$script" "$repo" "$input" 2>/dev/null | grep -cF "\$")" = 0 ]

name=resolves_symlinks
repo=$fixtures/repo-link
check [ "$(rendered '.permissions.rules[0].exclude[0]')" = "\"$real/repo\"" ]
repo=$fixtures/repo

name=rejects_missing_directory
refuses "$script" "$fixtures/missing" "$input"
refuses "$script" "$repo" "$fixtures/missing"

name=rejects_root
refuses "$script" / "$input"

name=rejects_glob_characters
refuses "$script" "$fixtures/glob*dir" "$input"
refuses "$script" "$repo" "$fixtures/brace{dir}"

src=$fixtures/checkout
dest=$fixtures/copy
mkdir -p "$src/sub/.kiro" "$src/.github" "$src/.git" "$src/.kiro/agents" "$dest"
echo a > "$src/a.txt"
echo b > "$src/sub/b.txt"
echo w > "$src/.github/w.yml"
echo s > "$src/sub/.kiro/s.md"
echo c > "$src/.git/config"
echo k > "$src/.kiro/agents/dependabot-review.json"
ln -s a.txt "$src/link.txt"
"$copy" "$src" "$dest" 2>/dev/null
listing=$(cd "$dest" && find . | LC_ALL=C sort | tr '\n' ' ')

name=copies_the_checkout
check [ "$(cat "$dest/a.txt" "$dest/sub/b.txt" "$dest/.github/w.yml" 2>/dev/null)" = $'a\nb\nw' ]

name=leaves_out_git_and_kiro
check [ "$listing" = '. ./.github ./.github/w.yml ./a.txt ./link.txt ./sub ./sub/.kiro ./sub/.kiro/s.md ./sub/b.txt ' ]

name=keeps_symlinks
check [ "$(readlink "$dest/link.txt")" = a.txt ]

name=copy_requires_an_empty_destination
refuses "$copy" "$src" "$dest"
refuses "$copy" "$src" "$fixtures/missing"

# The V3 engine is the one that loads an agent with permissions rules; the
# empty --trust-tools leaves those rules as the only grant.
name=runs_the_agent_on_v3
run=$(sed -n '/name: Rate the risk with Kiro/,/^    - name:/p' dependabot-review/action.yml)
while IFS= read -r want; do
  check grep -qF -- "$want" <<<"$run"
done <<'WANT'
args=(chat --v3 --no-interactive --agent dependabot-review --trust-tools=)
KIRO_HOME=$(mktemp -d
copy-checkout.sh" "$GITHUB_WORKSPACE" "$workspace"
render-kiro-agent.sh" "$workspace" "$RUNNER_TEMP/kiro-input"
(cd "$workspace" && timeout
WANT

exit $((failures > 0))
