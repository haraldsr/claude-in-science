#!/usr/bin/env bash
# Stop hook (hands-off bundles only): nothing is committed until the project's verification
# command passes. Nobody is watching to catch unverified work, so the gate does:
# CLAUDE_VERIFY_CMD (settings.json › env; /setup fills it in with the test command it saw
# pass) runs whenever tracked files have changed, and stop_autocommit.sh — chained after this
# with && — only runs if it passes.
#
# On failure the turn is held open (exit 2; the output goes to Claude) so the failure gets
# fixed. The same failing diff is raised once: raised again unchanged, the gate lets the turn
# end with nothing committed (exit 1 — the && chain stops, the message goes to the user), so a
# run that cannot fix it terminates instead of looping. Empty CLAUDE_VERIFY_CMD: no-op.
set -u
cd "${CLAUDE_PROJECT_DIR:-$PWD}" || exit 0
[ -n "${CLAUDE_VERIFY_CMD:-}" ] || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
git diff --quiet && git diff --cached --quiet && exit 0      # no tracked changes → nothing to verify

# `timeout` is GNU coreutils and absent on stock macOS — fall back rather than fail.
if command -v timeout >/dev/null 2>&1; then to="timeout ${CLAUDE_VERIFY_TIMEOUT:-600}"
elif command -v gtimeout >/dev/null 2>&1; then to="gtimeout ${CLAUDE_VERIFY_TIMEOUT:-600}"
else to=""; fi
out=$($to bash -c "$CLAUDE_VERIFY_CMD" 2>&1); rc=$?

cache="${XDG_CACHE_HOME:-$HOME/.cache}"
stamp="$cache/claude_verify_gate_$(pwd | cksum | cut -d' ' -f1)"
if [ "$rc" -eq 0 ]; then rm -f "$stamp" 2>/dev/null; exit 0; fi

key=$( { git diff; git diff --cached; } | cksum | cut -d' ' -f1)
tail_out=$(printf '%s\n' "$out" | tail -n 40)
if [ "$(cat "$stamp" 2>/dev/null)" = "$key" ]; then
  { echo "Verify gate: \`$CLAUDE_VERIFY_CMD\` still fails on the same diff — NOT committed. Last 40 lines:"
    printf '%s\n' "$tail_out"; } >&2
  exit 1
fi
mkdir -p "$cache" 2>/dev/null; printf '%s' "$key" > "$stamp" 2>/dev/null
{
  echo "Verify gate: \`$CLAUDE_VERIFY_CMD\` failed (exit $rc). Nothing is committed until it passes — fix the failure, or revert the change and record it as open in LESSONS.md. Last 40 lines:"
  printf '%s\n' "$tail_out"
} >&2
exit 2
