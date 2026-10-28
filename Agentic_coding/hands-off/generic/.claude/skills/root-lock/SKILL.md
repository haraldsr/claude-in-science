---
name: root-lock
description: Verify the agent is confined to the project ROOT and report the allowlist
disable-model-invocation: true
allowed-tools: Bash(pwd:*), Bash(echo:*), Bash(ls:*), Bash(test:*), Bash(git rev-parse:*), Read
---

Confirm root confinement is actually in force, then report it in a few lines.

1. Print ROOT: `echo "${CLAUDE_PROJECT_DIR:-$(pwd)}"`.
2. Confirm the guard exists and is executable:
   `test -x "$CLAUDE_PROJECT_DIR/.claude/hooks/block_outside_root.sh" && echo present`.
3. Read `.claude/settings.json` and confirm `block_outside_root.sh` is wired as a
   `PreToolUse` hook matching `Bash|Read|Edit|Write|NotebookEdit|Glob|Grep`. If it is not
   wired, say so loudly — the hook file alone enforces nothing. Also confirm
   `permissions.blockReadsOutsideWorkingDirectories` is **absent**: it is deliberately not
   used, because it turns every Bash command the shell parser cannot analyse into a permission
   prompt. If someone has added it, say so.
4. Live-test it: attempt `ls "$HOME"`. It MUST come back denied by the hook. If that
   command succeeds, confinement is BROKEN — report that as the headline.
5. Report, in at most five lines:
   - ROOT
   - wired: yes/no (hook + setting)
   - live test: denied (good) / allowed (BROKEN)
   - the allowlist in effect: ROOT, `$HOME/.cache`, `$TMPDIR` / `/tmp`, read-only
     system prefixes, plus anything in `$CLAUDE_ROOT_ALLOW`.

Rules while this is in force:
- Never read, write, list, or grep outside ROOT: not `$HOME`, not other users' homes, not
  other repositories, not group or scratch filesystems. Caches and job logs under
  `$HOME/.cache` are the one routine exception.
- If a task appears to need a path outside ROOT, STOP and ask the user. Do not disable,
  edit, or route around the hook, and do not add entries to `$CLAUDE_ROOT_ALLOW` yourself.
