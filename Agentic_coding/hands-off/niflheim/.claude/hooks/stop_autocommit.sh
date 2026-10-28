#!/usr/bin/env bash
# Stop hook: auto-commit changes to ALREADY-TRACKED files at the end of a turn, and push
# only if CLAUDE_AUTO_PUSH=1 (a personal choice: set it in .claude/settings.local.json
# under "env", or export it in your shell — never in the shared settings.json).
#
# Scope = tracked files only (`git add -u`): new/untracked files are never auto-added —
# stop_untracked_gate.sh holds the turn open until Claude decides what each one is. Runs
# after the gate (same Stop entry, chained with &&), so nothing is committed while strays
# are unresolved.
# No LLM, no API, no cost: the commit message is derived from the staged filenames.
# Never force-pushes.
set -u
cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

git add -u
git diff --cached --quiet && exit 0        # nothing staged → stay silent

staged=$(git diff --cached --name-only)
n_files=$(printf '%s\n' "$staged" | sed '/^$/d' | wc -l | tr -d ' ')
first_few=$(printf '%s\n' "$staged" | sed '/^$/d' | head -3 | tr '\n' ',' | sed 's/,$//; s/,/, /g')
more=$([ "$n_files" -gt 3 ] && echo " (+$((n_files - 3)) more)" || echo "")
msg="Update $first_few$more"

# Report to the user (systemMessage is user-facing; Claude does not see it).
say() { if command -v jq >/dev/null 2>&1; then jq -n --arg m "$1" '{systemMessage:$m}'; else printf '%s\n' "$1" >&2; fi; }

if ! commit_out=$(git commit -m "$msg" 2>&1); then
  say "Auto-commit FAILED ($n_files tracked file(s)):
$commit_out"
  exit 0
fi
head_short=$(git rev-parse --short HEAD 2>/dev/null)

if [ "${CLAUDE_AUTO_PUSH:-0}" != "1" ]; then
  say "Auto-committed $head_short \"$msg\" ($n_files tracked file(s)); not pushed — CLAUDE_AUTO_PUSH is unset."
  exit 0
fi

# `timeout` is GNU coreutils and absent on stock macOS — fall back rather than fail.
if command -v timeout >/dev/null 2>&1; then to="timeout 60"
elif command -v gtimeout >/dev/null 2>&1; then to="gtimeout 60"
else to=""; fi
if push_out=$($to git push origin HEAD 2>&1); then
  say "Auto-committed + pushed $head_short to origin: \"$msg\" ($n_files tracked file(s))."
else
  say "Auto-committed $head_short \"$msg\" ($n_files tracked file(s)) — but PUSH FAILED:
$push_out
The commit is safe locally; run /commit-push-pr or push manually to retry."
fi
exit 0
