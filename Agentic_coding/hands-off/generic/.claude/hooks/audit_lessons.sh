#!/usr/bin/env bash
# Stop hook: once per CALENDAR DAY, surface how many UNRECONCILED forward-looking
# promises live in the lessons log (NEXT/DEFERRED/NOT-yet/RESIDUAL/TODO). The log is
# append-only, so such lines pile up and are never marked done even after the work lands.
# This nudges a periodic skim so resolved items get ' [DONE]' and the open ones stay
# visible. Throttled to one nudge/day via a ~/.cache stamp.
#
# The nudge goes to CLAUDE (additionalContext), not just the user — a systemMessage is
# user-facing and Claude never sees it. Non-blocking; never edits. jq-missing => no-op.
set -u
cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 0
# First lessons log that exists wins: project log, then the portable one.
LF=""
for c in tasks/lessons.md LESSONS.md docs/lessons.md; do
  [ -f "$c" ] && { LF="$c"; break; }
done
[ -n "$LF" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

STAMP="${XDG_CACHE_HOME:-$HOME/.cache}/claude_lessons_audit_date"
today=$(date +%Y-%m-%d 2>/dev/null) || exit 0
[ "$(cat "$STAMP" 2>/dev/null)" = "$today" ] && exit 0   # already nudged today

# Lines that promise future work. DONE:-tagged lines are excluded (the convention
# for marking a promise resolved without deleting the historical entry).
open=$(grep -aiE "next:|next \(|deferred|not yet|residual|\btodo\b|\bopen\b" "$LF" 2>/dev/null \
        | grep -aivE "\bDONE\b|RESOLVED" | wc -l | tr -d ' ')
[ "${open:-0}" -eq 0 ] && exit 0

mkdir -p "$(dirname "$STAMP")" 2>/dev/null
echo "$today" > "$STAMP" 2>/dev/null
jq -n --arg m "Lessons audit (daily): $LF carries ~$open unreconciled forward-looking items (NEXT/DEFERRED/NOT-yet/RESIDUAL). When convenient this session, skim them — append ' [DONE — how]' to any since-resolved promise (keeps history, clears the queue) and leave the genuinely-open ones. List: grep -niE 'next:|deferred|not yet|residual|todo' $LF" \
  '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:$m}}'
exit 0
