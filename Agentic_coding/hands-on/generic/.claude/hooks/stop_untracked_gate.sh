#!/usr/bin/env bash
# Stop hook: the "clean up after yourself" gate.
#
# CLAUDE.md can only *ask* for cleanup; by the time a task ends, attention is on the report
# and the ask is forgotten. This makes it structural: if the turn is ending with untracked
# files in the tree (.gitignore respected — so scratch/ never counts), the stop is blocked
# ONCE (exit 2) and Claude gets the list in context. It must then delete, move to scratch/,
# gitignore, or `git add` each one before the turn can end. That also closes the "new file
# never got git add-ed" hole: auto-commit is tracked-files-only.
#
# Fires once per NEW set of strays: a file deliberately left untracked is raised once, then
# remembered (stamp under ~/.cache) until the set changes. Needs no jq.
set -u
cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
# Stay quiet while setup is pending: on a fresh install every harness file is untracked,
# so this would fire on turn one about files the user just copied in. /setup ends by
# committing them.
[ -f .claude/setup/SETUP_REQUIRED ] || [ -f .claude/setup/SETUP_IN_PROGRESS ] && exit 0
payload=$(cat 2>/dev/null || true)

strays=$(git ls-files --others --exclude-standard 2>/dev/null)
cache="${XDG_CACHE_HOME:-$HOME/.cache}/claude-stray-gate"
stamp="$cache/$(printf '%s' "$PWD" | cksum | cut -d' ' -f1)"
if [ -z "$strays" ]; then rm -f "$stamp" 2>/dev/null; exit 0; fi

key=$(printf '%s' "$strays" | cksum | cut -d' ' -f1)
[ "$(cat "$stamp" 2>/dev/null)" = "$key" ] && exit 0        # this exact set was already raised
mkdir -p "$cache" 2>/dev/null; printf '%s' "$key" > "$stamp" 2>/dev/null

# Claude already answered a block this turn — let the turn end.
printf '%s' "$payload" | grep -qE '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0

n=$(printf '%s\n' "$strays" | sed '/^$/d' | wc -l | tr -d ' ')
{
  echo "Stop gate: $n untracked file(s) left in the tree. Auto-commit is tracked-files-only, so these are invisible to it and will be lost or forgotten:"
  printf '%s\n' "$strays" | sed 's/^/  /'
  echo "For each one do exactly one of: delete it; move it to scratch/ (gitignored); add it to .gitignore; or \`git add\` it if it belongs in the repo. Then stop. If a file is the user's and not yours, say so and leave it."
} >&2
exit 2
