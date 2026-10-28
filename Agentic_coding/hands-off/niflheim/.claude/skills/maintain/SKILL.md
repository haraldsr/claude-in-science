---
name: maintain
description: One maintenance iteration — audit, verify every finding, fix one, commit; stop when nothing verified is left
disable-model-invocation: true
argument-hint: [directory or module to sweep; default: the whole tree]
allowed-tools: Read, Grep, Glob, Edit, Write, Bash, Agent
---

One iteration of the maintenance loop. Meant to run as `/loop 1d /maintain` (inside `tmux` on
a server) — so do **one** verified fix and stop; the next iteration takes the next one.
Everything in `CLAUDE.md` applies, in particular *Loops* and *Verify, then record*.

1. Read the `open:` items in `LESSONS.md`. Anything listed there is blocked on a human —
   don't redo it, don't work around it.
2. Fan out the read-only auditors in `.claude/agents/` over `$ARGUMENTS` (default: the whole
   tree, excluding `scratch/` and anything gitignored): `dead-code-finder`, `doc-auditor`,
   `config-auditor`, `bug-hunter`. Pass every finding through `verifier`. Drop what doesn't
   survive — an unverified finding is not a finding.
3. Pick ONE surviving finding, smallest and most certain first. Fix it as its own change:
   verify (the project's tests, and `CLAUDE_VERIFY_CMD` runs again before the commit), then
   commit with the finding and the evidence in the message.
4. Anything you could not fix, or that needs a decision only the user can make → one
   `- open: <what and why>` line in `LESSONS.md`. Don't retry it next iteration.
5. Stop condition: no surviving findings → say "nothing to do" and stop. Otherwise stop after
   the one fix. Never two in one iteration — the second one doesn't get a clean verification.
