# Setup checklist

What "set up correctly" means. `/setup` works through this; the gate lifts when every line is
either done or explicitly declined by the user. Deleted by `release.sh`.

## 1. The guards actually work

- [ ] `jq` is on PATH. Without it every guard fails closed and nothing can run.
- [ ] `bash .claude/hooks/test_hooks.sh` — **every line PASS**. A guard that does not guard is
      worse than none, because `CLAUDE.md` promises behaviour that then is not enforced.
- [ ] The project is a git repository with a remote, or the user has said they don't want one.
      Auto-commit, the stray-file gate and the destructive-git guard all assume git.

## 2. Context that loads every session

- [ ] `.claude/rules/project.md` exists and is filled in — not the template. This is where
      project facts live so that `CLAUDE.md` can stay identical across projects.
      It must answer, concretely: what this project is; where the code lives; the entrypoints;
      the build / test / lint commands; the non-obvious gotchas a newcomer gets wrong.
- [ ] Every command written there has been **run once and observed to work**. A wrong test
      command is worse than none: it makes "tests pass" unfalsifiable.
- [ ] `.claude/rules/data-integrity.md` — kept if this project reads, detects or scores
      values; deleted if it does not apply.

## 3. Context that loads on demand

- [ ] Every code directory the user agreed to has a `CLAUDE.md` in it — **verified with
      `ls`**, not assumed. Agreeing to one in the interview and not writing it is the failure
      this line exists to catch.
- [ ] Per-area context was **put to the user as a choice** — a nested `CLAUDE.md` in `src/`
      or a `.claude/rules/<area>.md` with `paths:` frontmatter, both of which load only when
      Claude touches matching files. Declining is a valid answer. Deciding it on the user's
      behalf is not: they end up with a config they never saw a choice about. The same goes
      for every other optional item on this list.
- [ ] Repeatable procedures with side effects are skills
      (`.claude/skills/<name>/SKILL.md`, `disable-model-invocation: true`), not prose.

## 4. Running things

- [ ] `RUNBOOK.md` exists **if** running things here is non-obvious — a cluster, a scheduler, a
      fragile environment. A repo where `npm test` just works needs none, and saying so counts
      as done.
- [ ] If one exists, its project section is filled in.
- [ ] No login node is recorded anywhere — not in the project section, not in
      `.claude/rules/`. `node_facts.sh` reads the node live each session; a written one is
      wrong the next time the session starts elsewhere.

## 5. Housekeeping

- [ ] `.gitignore` covers `scratch/`, `.claude/settings.local.json`, `CLAUDE.local.md`.
- [ ] `CLAUDE_VERIFY_CMD` in `settings.json` › `env` is the test command from §2, and it has
      been seen to pass once. Empty means the verify gate is off and unverified work can
      become HEAD — only with the user's explicit say-so.
- [ ] Push is on (`CLAUDE_AUTO_PUSH=1` in `settings.json`): the remote exists and one push
      has succeeded. Nobody is around to push by hand.
- [ ] `/context` shows `CLAUDE.md` and `.claude/rules/` under **Memory files**. If a file is
      not listed there, Claude cannot see it and writing it achieved nothing.
