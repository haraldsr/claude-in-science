#!/usr/bin/env bash
# SessionStart hook: while setup is pending, say so — loudly, and before any work starts.
#
# Pairs with block_until_setup.sh, which is the actual enforcement. This half exists because a
# denial with no explanation is worse than a denial with one: the agent should know on turn one
# what state the project is in and what to do about it, rather than discovering it by being
# blocked mid-task.
#
# No-ops the moment setup is released, and is deleted by release.sh.
set -u
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$proj/.claude/setup/SETUP_REQUIRED" ] || exit 0
command -v jq >/dev/null 2>&1 || { printf 'SETUP REQUIRED: run /setup before starting work.\n' >&2; exit 0; }

jq -n '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:"SETUP NOT COMPLETE. This project has the Claude Code harness installed but its context has not been laid out yet, so edits to source files are DENIED by a hook until it is.\n\nBefore doing anything the user asks for: tell them setup is pending and run /setup. It is an interview plus a set of checks — it works out where the code lives, what the build/test/lint commands are, whether a RUNBOOK is needed, and which areas need their own rules; it verifies the guard hooks actually work; then it releases the gate and deletes itself.\n\nIf the user insists on working first, say plainly that source edits will be denied until setup completes, and that .claude/setup/release.sh abandons setup if that is what they want. Do not try to route around the hook, and do not delete the marker file yourself."}}'
exit 0
