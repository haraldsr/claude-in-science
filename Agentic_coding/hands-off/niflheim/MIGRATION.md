# MIGRATION — install this setup into an existing project

You have been handed this folder inside an existing project that already has its own
`CLAUDE.md` and `.claude/`. Your job is to migrate that project onto this setup **without
losing anything that was in the old files**. Read this whole file before touching anything.

This is a multi-step task with an architectural decision in it, so: plan first, show the plan,
get a yes, then execute.

## What this setup is

Three files, three jobs — the split is the entire point of the migration:

| File | Holds | Where project-specific content is allowed |
|---|---|---|
| `CLAUDE.md` | Rules: how to act, what's forbidden, how to verify | **Never.** Byte-identical in every project |
| `RUNBOOK.md` | Mechanics: how to run things on this cluster | Only in the `## Project section` at the bottom |
| `LESSONS.md` | Append-only log of corrections | Yes — it's this project's log |

Plus `.claude/`: `settings.json` (permissions + hook wiring), `rules/data-integrity.md`
(hard constraints for pipelines that read / detect / score — keep it if the project is one),
`agents/` (6 read-only review subagents), `skills/` (4 user-invoked workflows), `bin/loginpy`
(bounded Python for a login node), `hooks/` (11 hooks + `test_hooks.sh`).

Guardrails are hooks, not sentences: `PreToolUse` hooks deny destructive git, `rm -rf`,
unbounded login-node Python and any path outside ROOT; a `Stop` gate holds the turn open while
untracked files remain. They fail **closed** — no `jq`, no tool call.

## Steps

**1. Inventory first, change nothing.** Report what the project currently has: the old
`CLAUDE.md` (line count), `.claude/{settings.json,settings.local.json,agents,commands,skills,
hooks,rules}`, any `LESSONS.md` / `tasks/lessons.md` / `docs/lessons.md`, `CLAUDE.local.md`,
`.gitignore`, and whether the tree is clean (`git status`). Do not delete anything yet.

**2. Sort the old `CLAUDE.md`, line by line, into four buckets.** Present the result as a
table and wait for a yes before writing any file:

- **Already covered** by the new `CLAUDE.md` (same rule, different words) → drop. Do not
  re-add the old phrasing; the new file states each rule once on purpose.
- **A behaviour rule that is genuinely missing** → propose adding it, quoted, with where it
  would go. Check it is really behaviour and not a project fact in disguise.
- **Machine mechanics** (partitions, modules, env vars, submit templates, ulimit tricks) →
  already in `RUNBOOK.md` above the project section, or add it there if it's new.
- **Project facts** (repo layout, module map, entrypoints, corpora, eval commands, domain
  rules, thresholds) → `RUNBOOK.md` › `## Project section`, or the project's own `README.md`.
  These are the reason the old file was too long. None of them go back into `CLAUDE.md`.
- **Not a fact at all**: which login node the project "runs from", its thread cap, whether
  the CPU-time limit applies there. Drop these — `node_facts.sh` reads them live each
  session, and a copy written down is wrong the next time the session starts elsewhere.

**3. Keep the lessons.** The old log's entries are history — carry them over verbatim, don't
rewrite them. `audit_lessons.sh` uses the first of `tasks/lessons.md`, `LESSONS.md`,
`docs/lessons.md` that exists, so either keep the old path (and let the new `LESSONS.md` go
unused) or merge into `LESSONS.md` and delete the old one. `CLAUDE.md` imports `LESSONS.md`
specifically, so prefer merging. If the merged log passes ~60 lines, move the `[DONE]`
entries to `LESSONS-archive.md` — moving, never deleting.

**4. Install.** From the project root, with this folder at `./niflheim/`:

```bash
cp -R niflheim/.claude niflheim/CLAUDE.md niflheim/LESSONS.md niflheim/RUNBOOK.md .
```

No `chmod` is needed — hooks are invoked as `bash <script>`.

Merge `niflheim/.gitignore` into the project's own (`scratch/`, `CLAUDE.local.md`,
`.claude/settings.local.json`) rather than overwriting it. Then:

```bash
bash .claude/hooks/test_hooks.sh
```

**Every line must say PASS.** If any fails, stop and report it — a guard that doesn't guard
is worse than no guard, because the rules in `CLAUDE.md` assume it works.

**5. Old `.claude/` contents.** List each old command, hook, agent and settings key, and say
what happens to it, before acting:

- `commands/*.md` → superseded by `skills/` (`/commit-push-pr`, `/sbatch-run`, `/root-lock`,
  `/niflheim-docs`). Anything the four don't cover becomes `.claude/skills/<name>/SKILL.md`
  with `disable-model-invocation: true` if it has side effects. Delete the old `commands/`
  only once its content is either migrated or confirmed dead.
- Old hooks → the shipped ones replace the earlier generation (the old `stop_git_reminder.sh`
  is now `stop_untracked_gate.sh` + `stop_autocommit.sh`). Any hook with no counterpart: name
  it and ask before dropping it.
- Old `settings.json` → the new one is authoritative for hooks and permissions. Carry over
  only project-specific `permissions.allow` entries and any `env` block, and say which.

**6. `settings.local.json`** (machine-local, gitignored — start from
`.claude/settings.local.json.example`): ask whether auto-**push** should be on
(`CLAUDE_AUTO_PUSH=1`; default off, commits still happen). If the project had a
`CLAUDE_LOGIN_SAFE_RE` allowlist, see the note under *What changed* before carrying it over.

**7. Verify and report.** `/root-lock` (must live-test as denied), `/context` shows
`CLAUDE.md` and `.claude/rules/` loaded, `git status` shows only intended changes. Report as a
diff summary: what moved where, what was dropped and why, what you're unsure about. Then
delete this `niflheim/` folder, and commit — one commit for the migration.

## Rules for this migration specifically

- **Nothing is deleted until it has been salvaged**, and deletions are asked for, not assumed.
  The old `CLAUDE.md` stays on disk (or in git history) until the user confirms the new split.
- **Nothing project-specific goes into `CLAUDE.md`.** If you are tempted, it belongs in
  `RUNBOOK.md` › Project section. This is the one rule the whole migration exists to enforce.
- **Don't improve the new files while installing them.** They are deliberate: each rule is
  stated once, emphasis is on almost nothing, the maintainer notes are HTML comments so they
  cost no context, and the file is at its 150-line budget. If you think something is wrong,
  say so — separately — rather than editing it in passing.
- The hooks are the enforcement layer. Don't loosen a matcher, add an allowlist entry, or
  route around a denial to get a step done; stop and ask instead.

## What changed versus the previous generation of this setup

Worth knowing, because the behaviour differs from what the project is used to:

- **Auto-push is now opt-in** (`CLAUDE_AUTO_PUSH=1`). Auto-commit of tracked files still
  happens every turn. `timeout` now falls back to `gtimeout`/none, so this works on macOS.
- **A Stop gate blocks the end of a turn** while untracked files exist, listing them to
  Claude. One-off files belong in `scratch/`.
- **The git guard is much broader**: it parses each command segment, sees through wrappers
  and `git -C`, and now also covers `restore`, `--amend`, `rebase`, `pull --rebase`,
  `stash drop|clear`, `+refspec` and `push --delete`.
- **Login-node Python is bounded, not banned.** The binding limit on Niflheim is the per-user
  thread cap (`ulimit -u`, varies by node), and NumPy/PyTorch/MKL default to one
  thread *per core* — so an uncapped import can want ~56 threads and `abort()` when a fork
  fails. `.claude/bin/loginpy` pins every pool to 1 and caps the wall clock, which makes quick
  checks safe; bare `python`, `pytest`, `pip` and `uv run` are still denied, wrappers
  included. If the project carried a `CLAUDE_LOGIN_SAFE_RE` allowlist, most of what it covered
  is better served by `loginpy` — propose retiring it rather than carrying it over unexamined.
- **A `SessionStart` hook asks for a documentation-drift check every 30 days**
  (`/niflheim-docs`, tunable with `CLAUDE_DOCCHECK_DAYS`). Where the project's RUNBOOK claims
  differ from what that check finds upstream, the check wins — report it rather than quietly
  keeping the old text.
- **Root confinement** also handles `~user`, `$VAR/…` and bare `..`, and is backed by
  `permissions.blockReadsOutsideWorkingDirectories`.
- **Commands are skills**, all `disable-model-invocation: true` — zero context cost until
  invoked, and Claude can't trigger them on its own.
- **Data-integrity constraints moved** out of `CLAUDE.md` into `.claude/rules/`. Same
  standing, same loading — delete that one file in a project where they don't apply.
