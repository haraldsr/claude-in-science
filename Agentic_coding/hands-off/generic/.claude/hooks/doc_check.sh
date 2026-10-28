#!/usr/bin/env bash
# SessionStart hook: now and then, remind Claude that the documentation this harness depends
# on should be re-read and the harness checked against it. Two checks, one stamp each, both
# every CLAUDE_DOCCHECK_DAYS (30):
#   /harness-docs   Claude Code best practices and changelog, against CLAUDE.md, the hooks,
#                   skills, agents and settings.json
#   /niflheim-docs  the cluster docs, against RUNBOOK.md — only where that skill is installed
#
# Why rare rather than every session: what changes upstream — a model generation, a renamed
# hook field, a partition retired — changes on the order of months, while the fetch costs a
# turn and a few thousand tokens. A harness that moves every week is one nobody can learn,
# and frequent "no change" turns teach everyone to ignore the nudge. CLAUDE_DOCCHECK_DAYS=0
# disables both.
#
# Costs nothing when not due: no network here, just a stamp file's date. The skills write the
# stamps when they finish.
set -u
command -v jq >/dev/null 2>&1 || exit 0
DAYS="${CLAUDE_DOCCHECK_DAYS:-30}"
[ "$DAYS" = "0" ] && exit 0
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"

due=""
check() {  # check <skill> <stamp file> <what it does>
  local stamp="$CACHE/$2" when
  if [ -f "$stamp" ]; then
    [ -n "$(find "$stamp" -mtime +"$DAYS" 2>/dev/null)" ] || return 0   # not yet due
    when="last checked $(head -1 "$stamp" 2>/dev/null), due every $DAYS days"
  else
    when="never checked on this machine"
  fi
  due="$due
- /$1 — $3 ($when)"
}
check harness-docs claude_harness_doccheck \
  "re-reads the Claude Code best-practices guide and changelog and reports where CLAUDE.md, the hooks and settings.json have drifted from them"
[ -f "$ROOT/.claude/skills/niflheim-docs/SKILL.md" ] && \
  check niflheim-docs claude_niflheim_doccheck \
  "re-reads https://niflheim-users.readthedocs.io and reports where RUNBOOK.md has drifted from it"
[ -z "$due" ] && exit 0

jq -n --arg m "Docs check due:$due
When there is a natural pause this session, run the skill(s) above. Don't interrupt work in progress for it, and don't run it silently in the background." \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
exit 0
