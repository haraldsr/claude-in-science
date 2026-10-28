#!/usr/bin/env bash
# SessionStart hook: read what differs by login node, live, and hand it to Claude.
#
# The login node is not fixed — a session runs on whichever node it was started on — and the
# things that differ by node (hostname, $CPU_ARCH, the per-user thread cap, whether the
# 20-minute CPU-time limit applies, which partitions it fronts) are exactly the things that
# went stale when they were written into RUNBOOK.md as constants. So none of them are written
# down: this prints the live values plus the node's own row of RUNBOOK.md's login-node table,
# which is labelled as site-documented values that the live ones override.
#
# Re-runs after /compact. Off-cluster it reports "not in table", which is harmless.
set -u
command -v jq >/dev/null 2>&1 || exit 0
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

host=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)
arch="${CPU_ARCH:-unset}"
cap=$(ulimit -u 2>/dev/null || echo unknown)
used=$(ps -u "${USER:-$(id -un)}" -o nlwp= 2>/dev/null | awk 'NF{s+=$1;n++} END{print (n ? s : "unknown")}')
# The row whose first cell names this host — the whole name in backticks, so a node whose
# name is a prefix of another's does not match the other's row.
row=$(grep -E "^\|[^|]*\`${host}\`" "$ROOT/RUNBOOK.md" 2>/dev/null | head -1)
[ -n "$row" ] || row="not in table"

ctx="Login node, read live — the node is not fixed, and nothing in RUNBOOK.md or .claude/rules/ names one: hostname=$host CPU_ARCH=$arch ulimit -u=$cap threads in use=$used. RUNBOOK.md login-node table row: $row. Live values win over the table; where they disagree, say the table is stale rather than trusting it. The CPU-time-limit column of that row decides whether a long login-node session (tmux, a raised LOGINPY_TIMEOUT) is safe here."
jq -n --arg ctx "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
