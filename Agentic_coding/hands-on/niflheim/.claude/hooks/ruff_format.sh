#!/usr/bin/env bash
# PostToolUse hook: after Claude edits a Python file, auto-format it with ruff
# and apply ruff's SAFE lint fixes.
#
# Why ruff (vs black + flake8): a single Rust binary, no Python stack imported, one
# short process per edit — cheap enough to run on every write, safe on thread-limited
# hosts. It runs directly from the hook, not through the Bash tool.
#
# Non-blocking by design: always exits 0 so a formatting hiccup never fails the
# edit, and silently no-ops if ruff isn't installed yet. Only touches .py files.
#
# CAVEAT: `ruff check --fix` applies SAFE fixes, which includes removing unused
# imports (F401). If a module is imported purely for a registration / side
# effect, that import can be stripped. If that ever bites, either drop the
# `check --fix` line below or mark the import `# noqa: F401`.
set -u

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
file=$(jq -r '.tool_input.file_path // empty')
[ -z "$file" ] && exit 0
case "$file" in
  *.py) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

# Prefer the project venv's ruff; fall back to one on PATH.
ruff="$proj/.venv/bin/ruff"
[ -x "$ruff" ] || ruff=$(command -v ruff 2>/dev/null)
[ -n "$ruff" ] || exit 0

# Format, then apply safe lint fixes. Quiet; never fail the edit.
"$ruff" format -- "$file" >/dev/null 2>&1
"$ruff" check --fix --quiet -- "$file" >/dev/null 2>&1
exit 0
