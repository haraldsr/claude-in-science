#!/usr/bin/env bash
# PreToolUse hook: block recursive-force deletes (`rm -rf` and equivalents).
# One stray rm -rf can irreversibly wipe the repo, the .venv, or NFS $HOME.
# Plain `rm -r` or `rm -f` ALONE are NOT blocked here (they still go through the
# normal permission prompt); only the recursive+force combination — the one that
# deletes without ever asking — is denied and bounced back to the user for an
# explicit decision. `find … -delete` is treated as the same thing.
# Fail CLOSED: if jq is missing, deny. Probe it with test_hooks.sh.
set -u
if ! command -v jq >/dev/null 2>&1; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"jq missing from PATH — rm guard cannot parse the command, blocking for safety (fail-closed)."}}'
  exit 0
fi
cmd=$(jq -r '.tool_input.command // ""')

deny() {
  jq -n --arg cmd "$cmd" --arg what "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:($what + " blocked: " + $cmd + "\n\nThis deletes recursively without prompting and can wipe the repo, the .venv, or your NFS home in one shot. It needs an explicit human decision — STOP and ask the user to run it themselves, or delete specific paths without the combo (e.g. `rm <file>`, or `rm -i` for an interactive prompt).")}}'
  exit 0
}

# A command boundary: start of line, whitespace, a shell separator, or the opening quote of
# an inline script (`bash -c "rm -rf x"`, `sh -c 'rm -rf x'`).
sep='(^|[[:space:]]|[;&|`(]|-l?c[[:space:]]*["'"'"'])'

# Extract each `rm` invocation with its args, up to the next shell separator. Anchored at a
# boundary with an optional path prefix (/bin/rm) and optional sudo, so "alarm" / "disarm"
# / arbitrary paths containing "rm" do NOT match.
rm_segs=$(printf '%s\n' "$cmd" | grep -oE "$sep"'([^[:space:];&|`)(]*/)?(sudo[[:space:]]+)?rm[[:space:]][^;&|`)]*')

# A segment is dangerous only if that SAME rm carries BOTH a recursive flag
# (-r / -R / a bundle like -rf / --recursive) AND a force flag (-f / --force).
# The two greps are piped so both conditions must hold on the same line.
if printf '%s\n' "$rm_segs" | grep -E '(-[A-Za-z]*[rR][A-Za-z]*|--recursive)' | grep -qE '(-[A-Za-z]*f[A-Za-z]*|--force)'; then
  deny "Recursive-force delete"
fi

# find … -delete removes every match, recursively, without prompting: same thing.
if printf '%s\n' "$cmd" | grep -qE "$sep"'([^[:space:];&|`)(]*/)?(sudo[[:space:]]+)?find[[:space:]][^;&|`)]*[[:space:]]-delete([[:space:]]|$)'; then
  deny "find -delete (recursive delete)"
fi
exit 0
