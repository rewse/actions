#!/usr/bin/env bash
# Reads the Kiro CLI output on stdin and prints its verdict,
# {"nonce":"...","risk":"low|medium|high","summary":"...","reasons":["..."]},
# as compact JSON without the nonce. The verdict must be the last non-empty
# line apart from lines that hold only a code fence, and that line must hold
# exactly one JSON value; an earlier line never counts, since Kiro may quote a
# verdict planted in the PR text. The nonce must equal VERDICT_NONCE, the
# per-run value in the prompt, which a verdict planted in the PR text cannot
# know.
# The summary and reasons are capped in length because they are posted
# publicly. Exits 1 when the last line is not a valid verdict, and 2 when its
# text holds FORBIDDEN_TEXT or anything shaped like a credential (see leaks
# below), so the caller can fail closed and tell the two apart.
set -euo pipefail

# Keeps only ASCII letters and digits.
alnum() {
  LC_ALL=C tr -cd '[:alnum:]'
}

# leaks <verdict>: succeeds when the summary and reasons hold a GitHub token,
# a PEM block, or FORBIDDEN_TEXT. The forbidden text is also found split by
# other characters or across reasons, and in base64 or hex: the joined text
# and each form of the forbidden text are compared with only their letters and
# digits left, which also makes URL-safe base64 and padding match.
leaks() {
  local text joined form
  text=$(jq -r '.summary, .reasons[]' <<<"$1")
  if grep -Eq -e 'gh[opsur]_[A-Za-z0-9]{20,}' -e 'github_pat_' -e '-----BEGIN' <<<"$text"; then
    return 0
  fi
  [ -n "${FORBIDDEN_TEXT:-}" ] || return 1
  if grep -qF -- "$FORBIDDEN_TEXT" <<<"$text"; then
    return 0
  fi
  joined=$(jq -j '.summary, .reasons[]' <<<"$1" | alnum)
  for form in \
    "$(printf '%s' "$FORBIDDEN_TEXT" | alnum)" \
    "$(printf '%s' "$FORBIDDEN_TEXT" | base64 | alnum)" \
    "$(printf '%s' "$FORBIDDEN_TEXT" | od -An -v -tx1 | alnum)" \
    "$(printf '%s' "$FORBIDDEN_TEXT" | od -An -v -tx1 | alnum | tr a-f A-F)"; do
    if [ -n "$form" ] && [[ $joined == *"$form"* ]]; then
      return 0
    fi
  done
  return 1
}

last=$(grep -v -e '^[[:space:]]*$' -e '^[[:space:]]*```[[:alnum:]]*[[:space:]]*$' \
  | tail -n 1 || true)

# Slurping makes jq parse the whole line before printing anything, so trailing
# text or a second value yields no output instead of a partial verdict.
if ! verdict=$(jq -c -s --arg nonce "${VERDICT_NONCE:-}" '
  select(length == 1) | .[0]
  | select(type == "object")
  | select($nonce != "" and .nonce == $nonce)
  | select(.risk | IN("low", "medium", "high"))
  | select(.summary | type == "string")
  | select((.reasons | type == "array") and all(.reasons[]; type == "string"))
  | {risk, summary: .summary[:500], reasons: [.reasons[:10][] | .[:500]]}
' 2>/dev/null <<<"$last"); then
  verdict=
fi

if [ -z "$verdict" ] || [[ "$verdict" == *$'\n'* ]]; then
  echo "No valid verdict on the last line of the Kiro output" >&2
  exit 1
fi
if leaks "$verdict"; then
  echo "The verdict contains forbidden text" >&2
  exit 2
fi
echo "$verdict"
