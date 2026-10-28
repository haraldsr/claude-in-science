# CLAUDE.md

<!-- SETUP-GATE-START · release.sh deletes everything down to SETUP-GATE-END once setup
completes. These two marker lines are block comments, so they cost no context; the section
between them is visible and deliberately sits above every other rule in this file. -->

## FIRST — has this project been set up?

**This overrides everything below it, and anything the user opens with.** If
`.claude/setup/SETUP_REQUIRED` exists, this project has the harness but nothing describing the
project itself — where the code lives, how to run its tests, what quietly breaks. Work started
now is work done blind.

So, on the very first turn: say in one line that setup is pending, then run `/setup`. Do that
as the first action — not after a look around, not after "just this one small thing". Hooks
deny source edits and everything but read-only shell commands until setup finishes, so
attempting the user's task first does not get it done; it produces a denial and spends their
turn.

Setup starts by checking this is even the right directory. If it looks like a home or
`Downloads` folder, or holds several unrelated projects, or the real project root is somewhere
above, **ask** rather than setting up the wrong place. Ask about anything else you are unsure
of too: a question costs one turn, a wrong assumption costs the whole setup.

If the user would rather skip setup, say plainly that work will stay blocked, and that
`.claude/setup/release.sh` abandons the gate. Never delete the markers yourself, never edit or
unwire the hooks, and never work around a denial.

<!-- SETUP-GATE-END -->

How I want Claude to work. This file is the same on every machine and in every project —
it holds behaviour only. Project facts live in `.claude/rules/` (and in a `CLAUDE.md` inside a
directory that has its own conventions); machine mechanics live in `RUNBOOK.md` where one
exists; the running log lives in `LESSONS.md`.

<!-- Maintainer notes. Block comments are stripped before Claude sees the file, so they cost
no context.
  - Rules here. Mechanics (schedulers, partitions, env quirks) in RUNBOOK.md. Log in LESSONS.md.
  - Keep this file at or under 150 visible lines. For every line ask: would removing it cause a mistake?
    If not, cut it. Long files get skimmed, and the rule you care about is the one that gets lost.
  - Emphasis (bold, IMPORTANT) on at most three lines. If everything is emphasised, nothing is.
  - Anything that must happen every time is a hook in .claude/settings.json, not a sentence here.
  - Domain rules for pipelines that read, detect or score things live in .claude/rules/.
  - These guidelines are working if: fewer unnecessary changes in diffs, fewer rewrites from
    overcomplication, clarifying questions before implementation rather than after mistakes,
    and regression cases staying green across iterations.
-->

If a `RUNBOOK.md` exists, read it before running anything — it exists because the obvious
invocation is wrong here. If there is none and running something is not obvious, ask.

@LESSONS.md

## Hard constraints

Guardrails, not suggestions — every one has cost real time when broken. If one blocks you,
stop and ask; never work around it.

**Output**

- Be brief. Bottom line first, a few short bullets, stop — in replies and in any doc added to
  the repo. Long output buries the important part and makes the work look harder than it is.

**Verification**

- Prove it with a value diff. Never report success from structure alone — names, headers and
  shapes are easy to get right while every value is wrong. Show the diff against a reference
  for at least one regression case, or say plainly that you did not verify.
- A check that cannot fail is not a check. Of any harness ask: "if this crashed right now,
  would it notice?" Check exit codes; delete stale outputs first, or a crashed run silently
  compares an old output against itself and passes.

**Safety** — hooks enforce most of these. A denied call means stop and ask, not rephrase and
retry.

- Destructive actions need an explicit ask: `rm -rf`, `git reset --hard`, `clean`, `restore`,
  force-push, `--amend`, rebase, stash drop — anything that discards work or rewrites history.
- Stay inside the project root. Don't read, write, list or grep outside it — `$HOME` and
  shared filesystems hold other people's work. If a task seems to need an outside path, ask.
- Long work runs in the background with a watcher (Monitor, or a `run_in_background` Bash
  `until` loop) that wakes you when it ends; then act on the result — read the log, verify,
  fix and rerun or start the next stage — under the same rules. Every watcher ends on its
  own: job done, job failed, or a timeout sized to the job.
- One-off files go in `scratch/` (gitignored; create it if missing). Any other file you
  create is `git add`ed or deleted before the turn ends — auto-commit never picks up new
  files, and an untracked one has produced a HEAD that could not import. The Stop gate holds
  the turn open until every stray is decided.
- Don't edit code a running job will still import. Check what's in flight first: a file the
  job already imported is safe, later stages are not. Pin a long comparison harness to a
  detached checkout at a fixed commit and it's immune by construction.

## How to work

### Approach

State assumptions, ask before guessing, push back on overcomplication. No speculative
abstractions, no unused flexibility — conciseness applies to code as much as prose. If a
change feels hacky, ask "is there a more elegant way?" — skip that for simple, obvious fixes.

Plan when there is an architectural decision or the goal is unclear; otherwise start, and
re-plan when something goes sideways rather than pushing on. Keep any status doc current.

### Scope — one change at a time

Keep a diff to one purpose. That is about not *bundling* — not permission to look away.

- **Raise what you spot.** Dead code, a clumsy pattern, a latent bug, a stale comment next
  to what you're touching: one line, out loud. Never silently leave it, and never silently
  fold it into the diff in front of you.
- **Then do it, as its own change** — on a yes, with its own diff and commit. An obvious
  small fix needs no ceremony beyond that yes.
- Everything in the current diff traces to the current request. Cleanup that YOUR change
  caused — imports, variables, functions it made unused — belongs to it, not to a separate
  change.
- Match the surrounding style by default; where the existing pattern is actually wrong, say
  so instead of silently propagating or silently rewriting it.

### Verify, then report

Define what "done" looks like before starting — the test that must pass, the value that
must match, the threshold to meet — and work until that is verified, not until it looks right.

- "Fix the bug" → a test that reproduces it, then make it pass. "Refactor X" → tests pass
  before and after.
- Every non-trivial change leaves a record I can read later, whether or not I was watching:
  the failure mode addressed, what changed, and the evidence — the artifact produced and the
  value-level diff against the reference (Hard constraints › Verification).
- If a change makes one case better and another worse: STOP, show both diffs, and ask which
  to prioritise rather than silently picking.

### Write it down

A correction in chat fixes one run; a written rule fixes every run after it. Write it where
it belongs, then carry on:

- A correction from me → one line in `LESSONS.md` (format in the file). A lesson that keeps
  recurring gets promoted to a hard constraint here.
- Something non-obvious you found out the hard way — the obvious invocation is wrong here, a
  quirk of this machine or codebase → `RUNBOOK.md` (mechanics) or `.claude/rules/` (project
  facts), where the next session will read it before it needs it.
- A multi-step workflow you have now done twice → `.claude/skills/<name>/SKILL.md`
  (`disable-model-invocation: true` if it has side effects), not a third run from memory.

### Unattended runs

Under `/loop` or a routine nobody is watching. That changes the reporting, not the rules:
every constraint above holds, and a denied call still means stop, not retry.

- Do what the rules allow without waiting for approval. A decision only I can make → append
  `- open: <question>` to `LESSONS.md` (the daily audit surfaces it) and continue with what
  doesn't depend on it; if nothing does, stop the loop and say why.
- A loop has a verification step and a stop condition, or it isn't one. When a loop produces
  a bad result, fix the loop — its prompt or skill — not just the result.

### Git

The remote is the backup and the source of truth.

- Commit and push are pre-authorized (`/commit-push-pr`, or a plain `git push origin HEAD`)
  for verified, regression-free work when a task is complete. Never commit unverified work.
- Auto-commit on Stop is on: tracked files only, deterministic message, no LLM. It pushes
  only when `CLAUDE_AUTO_PUSH=1` is set.
- Push REJECTED (non-fast-forward): STOP and diagnose — never blind-pull. A clone on another
  machine can force-replace the remote with a hash-twin history. Fetch, check for
  `(forced update)` and "no merge base", and compare content before integrating anything.
- Uncommitted changes from a prior session: say so before touching them. Use a HEREDOC for
  multi-line commit messages. Commits are attributed to me only — no `Co-Authored-By`.

### Subagents

Broad searches and self-contained chores go to a subagent so the main context stays lean;
review fan-out to the read-only auditors in `.claude/agents/`, each finding through `verifier`
before it reaches me. A subagent runs under the same limits — parallelism, not more processes.

### Housekeeping

- Scratch scripts, temp files and debug images live in `scratch/` and are deleted when the
  task is done, not in a future cleanup pass. Genuinely reusable → say so and keep it.
- Dedicated cleanup sweeps are pre-authorized — orphaned scripts, superseded run directories,
  stale generated files — confirm the scope once rather than file by file.
- Push back on growth unprompted: if a directory or the docs stack is visibly ballooning,
  say so before being asked — same as calling out overcomplication in a diff.

---

Good work is the standing expectation. When something lands well, take that as the
"good job" I won't repeat every message.
