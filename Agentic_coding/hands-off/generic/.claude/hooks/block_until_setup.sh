#!/usr/bin/env bash
# PreToolUse hook (Bash|Edit|Write|NotebookEdit): the setup gate's teeth.
#
# CLAUDE.md's opening section is what makes Claude *run* /setup first — a hook can only refuse
# things, it can never make anything happen. This half exists for when that instruction is not
# followed: a fresh session opened with a concrete task is exactly the case where an
# instruction gets skipped, so the ordering is made structural rather than hopeful.
#
# Two phases, keyed on marker files under .claude/setup/:
#
#   SETUP_REQUIRED      nothing has started. Bash is limited to read-only inspection, and the
#                       only writable files are the ones setup itself produces.
#   SETUP_IN_PROGRESS   /setup is running (it writes this marker as its first act). Bash opens
#                       up, because verifying the build/test/lint commands means running them —
#                       that IS the setup. Source files stay read-only.
#   neither             released. This hook exits immediately and costs nothing.
#
# Deliberately not airtight: it gates the tools, not every conceivable shell trick. It exists
# to stop the agent plowing ahead, not to defend against a determined bypass — which is why
# routing around it is a CLAUDE.md violation rather than something to engineer against.
set -u
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
req="$proj/.claude/setup/SETUP_REQUIRED"
prog="$proj/.claude/setup/SETUP_IN_PROGRESS"
[ -f "$req" ] || [ -f "$prog" ] || exit 0

if ! command -v jq >/dev/null 2>&1; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"jq missing from PATH — the setup gate cannot parse the call, blocking for safety (fail-closed). Install jq, then run /setup."}}'
  exit 0
fi

payload=$(cat)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // ""')

deny() {
  jq -n --arg what "$1" --arg extra "$2" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("SETUP NOT COMPLETE — " + $what + " denied.\n\nThis project has the harness installed but nothing yet describes the project itself: where the code lives, how to run its tests, what breaks. Work started now is work done blind, so it is gated.\n\nRun /setup. It reads the repo, asks the user what it cannot determine, writes .claude/rules/project.md, runs each command it records to prove the command works, checks the guard hooks, then removes this gate.\n" + $extra + "\nIf the user wants to skip setup entirely, .claude/setup/release.sh abandons it. Do not delete the markers yourself, and do not edit or unwire the hooks to get moving.")}}'
  exit 0
}

case "$tool" in
  Edit|Write|NotebookEdit)
    f=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
    [ -n "$f" ] || exit 0
    case "$f" in "$proj"/*) rel="${f#"$proj"/}" ;; *) rel="$f" ;; esac
    case "$rel" in
      CLAUDE.md|LESSONS.md|LESSONS-archive.md|RUNBOOK.md|README.md|.gitignore|CLAUDE.local.md) exit 0 ;;
      AGENTS.md|.claude/*|scratch/*|*/CLAUDE.md) exit 0 ;;
    esac
    deny "editing $rel" "\nWritable meanwhile: CLAUDE.md, LESSONS.md, RUNBOOK.md, README.md, .gitignore, nested CLAUDE.md files, and anything under .claude/ or scratch/. If setup genuinely needs this file changed, say which and why and ask the user.\n"
    ;;
  Bash) ;;
  *) exit 0 ;;
esac

# While /setup is running, it needs to run the project's own commands to verify them.
[ -f "$prog" ] && exit 0

cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
[ -n "$cmd" ] || exit 0

# A redirection writes a file whatever the command in front of it is. Discards are not
# writes, though: `2>/dev/null` and `2>&1` are ordinary in read-only inspection, so strip
# those forms first and only object to what is left.
probe=$(printf '%s' "$cmd" | sed -E 's/[0-9]*>&[0-9-]+//g; s/&?[0-9]*>>?[[:space:]]*\/dev\/null//g')
case "$probe" in *'>'*) deny "a shell redirection" "\nBefore setup, Bash is limited to read-only inspection: no writes, no builds, no test runs. Discarding output (2>/dev/null, 2>&1) is fine; writing a file is not.\n" ;; esac

# Read-only inspection, plus the few commands setup and installation themselves need.
allowed_word() {
  case "$1" in
    ls|cat|head|tail|grep|egrep|fgrep|rg|find|fd|wc|file|stat|du|df|which|type|echo|printf|pwd|tree|basename|dirname|sort|uniq|cut|column|jq|diff|cmp|uname|whoami|date|true|test|mkdir|chmod|command|sinfo|squeue|sacct|scontrol|ulimit) return 0 ;;
  esac
  return 1
}

# One check per segment: a chain is only as read-only as its least read-only part.
# Split $probe, not $cmd — the `&` in a stripped `2>&1` would otherwise look like a separator
# and leave a bare `1` behind as its own "command".
printf '%s\n' "$probe" | tr ';&|()`' '\n' | while IFS= read -r seg; do
  set -- $seg
  [ $# -eq 0 ] && continue
  while [ $# -gt 0 ]; do case "$1" in *=*) shift ;; *) break ;; esac; done   # VAR=value prefixes
  [ $# -eq 0 ] && continue
  w="$1"; shift
  case "$w" in
    ./install.sh|install.sh|.claude/setup/release.sh|./.claude/setup/release.sh) continue ;;
    bash|sh) case "${1:-}" in .claude/*|./.claude/*) continue ;; esac ;;
    git) case "${1:-}" in status|log|diff|show|ls-files|rev-parse|remote|config|branch|describe|blame|shortlog) continue ;; esac ;;
  esac
  allowed_word "$w" && continue
  printf '%s' "$w" > "$proj/.claude/setup/.blocked_word" 2>/dev/null
  exit 17
done
[ $? -eq 17 ] || exit 0

w=$(cat "$proj/.claude/setup/.blocked_word" 2>/dev/null); rm -f "$proj/.claude/setup/.blocked_word" 2>/dev/null
deny "the command \`$w\`" "\nBefore setup, Bash is limited to read-only inspection — ls, cat, grep, find, read-only git, and the setup's own scripts. Builds, test runs and anything that writes are denied until /setup starts; once it does, they are allowed, because running them is how setup proves the commands it records actually work.\n"
