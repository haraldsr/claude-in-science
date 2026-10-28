# Claude Code setup

Four self-contained bundles: the row is how you work, the column is where the code runs. Pick
one, copy its **contents** into your project, done — no prior setup, nothing else to fetch.

| | `generic/` — any project, any machine | `niflheim/` — the DTU Niflheim cluster |
|---|---|---|
| **`hands-on/`** — you prompt, read, approve | `CLAUDE.md`, `LESSONS.md`, rules, 6 subagents, 3 skills, 9 hooks + a hook test | everything in `generic/`, **plus** `RUNBOOK.md`, 4 cluster hooks, 3 cluster skills, `loginpy`, `MIGRATION.md` |
| **`hands-off/`** — you brief it or write a loop, and read the result | the same, with auto mode, a verify gate before every commit, push on, and `/maintain` | the same, on the cluster |

All four ship **gated**: a fresh install refuses to edit source files until `/setup` has laid
out the project's context. See *The setup gate*.

The *Claude in Science* workshop page (`../Claude_in_Science_workshop/`) walks through
installing `hands-on/niflheim`; keep its Setup section in step with *Install* below.

## Hands-on or hands-off

The two rows are different tools, not a setting. Hands-on assumes you are there: Claude asks
before guessing, shows you the evidence, stops at a permission prompt. Hands-off assumes you
are not: nothing may block on you, and nothing unverified may become HEAD. One `CLAUDE.md`
cannot say both — Claude can't reliably tell which situation it is in — so they are separate
bundles, and they are **meant to drift apart**.

### Which row

A question about the verifier, not about trust. Hands-off works when a check can run without
you and a wrong iteration is cheap: the tests pass or they don't, the diff matches the
reference or it doesn't, and a bad attempt costs minutes and a revert. Hands-on is for work
where the check is your judgement, or where one iteration costs real compute.

| Work | Row | Because |
|---|---|---|
| Developing, refactoring, testing code; docs; cleanup | `hands-off/` | tests are the verifier; a wrong attempt costs minutes |
| Setting up a DFT / MD / simulation workflow, choosing parameters, interpreting results, the first run of anything | `hands-on/` | the verifier is you; a wrong 24-core, 24-hour job is not cheap |
| Running a proven pipeline over many inputs, resubmitting failures | `hands-off/` once the sanity checks are mechanical (exit code, converged, file present); `hands-on/` until then | the check is a script, not a scientist |

In practice that is one row per repository: the code package is `hands-off/`, the
calculations directory next to it is `hands-on/`.

### What differs

| | `hands-on/` | `hands-off/` |
|---|---|---|
| Permission mode | `default` — prompts for anything not pre-allowed | `auto` in `settings.json`: a classifier approves safe actions and flags destructive ones; the hooks deny those whatever the mode |
| A decision only you can make | Claude asks and waits | `- open: …` in `LESSONS.md`; continues with what doesn't depend on it; stops if nothing does |
| Evidence | shown to you each turn | in the commit message |
| One case better, one worse | stop, show both, ask | not committed; both diffs recorded as open |
| Commit | after the stray-file gate | after the stray-file gate **and** `CLAUDE_VERIFY_CMD` passes (`stop_verify_gate.sh`); then pushed |
| Loops | — | `/maintain`: one verified fix per iteration; `/loop 1d /maintain` |

The guard hooks — destructive git, `rm -rf`, root confinement, login-node Python — are the
same in all four and should stay so: a fix to one is copied to the other three. Nothing
enforces it; the bundles differ on purpose, and a check would have to know which differences
are meant.

Hands-off, two things to know:

- `/loop` runs on your machine and dies with the `claude` process. On a server that means a
  `tmux` session (`niflheim/RUNBOOK.md` › Login nodes). Routines (`/schedule`) run in the
  cloud on a fresh clone — fine for a repo on GitHub/GitLab, no use for anything that has to
  reach a cluster.
- The loop is the easy part. Its prompt needs a verification step and a stop condition, or it
  runs until the budget does. When the loop produces a bad result, fix the loop, not the
  result (`CLAUDE.md` › Loops).

## Install

There is no install script — copy the bundle's **contents** into the project root (not the
folder itself), merge its `.gitignore`, and run the hook tests:

```bash
B=hands-on/generic; P=<project>  # or hands-on/niflheim, hands-off/generic, hands-off/niflheim
cp -R $B/.claude $B/CLAUDE.md $B/LESSONS.md $P/        # niflheim: add $B/RUNBOOK.md
touch $P/.gitignore && grep -vxFf $P/.gitignore $B/.gitignore >> $P/.gitignore
(cd $P && bash .claude/hooks/test_hooks.sh)            # every line must say PASS
```

Then open Claude Code in the project and give it a task; it will tell you setup is pending and
run **`/setup`**. Until it completes, edits to source files are denied — see *The setup gate*
below.

- **Project already has a `CLAUDE.md` or `.claude/`?** Don't copy over it — `cp` silently
  overwrites both. Use `<row>/niflheim/MIGRATION.md` instead (see *Migrating an existing project*).
- **Don't overwrite `.gitignore`.** The `grep` line above appends only the lines the project
  doesn't already have.
- **Copying in Finder?** `.claude/` and `.gitignore` are hidden — ⌘⇧. shows them, or they are
  silently left behind.
- No `chmod` needed. Every hook is invoked as `bash <script>` precisely so that a copy which
  lost its executable bits still works — an unexecutable hook invoked directly exits 126, which
  the hook system treats as a *non-blocking* error, silently disarming every guard.
  `test_hooks.sh` asserts the wrapper stays in place.

- Every guard hook needs `jq` on PATH. They fail **closed**: no `jq`, no tool call.
- Your first session shows Claude Code's trust dialog listing the permission allow-rules from
  `settings.json`. Hooks run regardless; accept the dialog to get the pre-approved git commands.
- `.claude/rules/` and `.claude/skills/` need a current Claude Code (2.1.x).
- Auto-commit on Stop is on. Auto-**push** is off until you set `CLAUDE_AUTO_PUSH=1` — in your
  `settings.local.json` `env` block or your shell. Personal choice, so it's not in the shared file.

## The setup gate

A bundle dropped into a project is only half a setup: `CLAUDE.md` carries the rules, but
nothing yet says what the project *is* — where the code lives, how to run its tests, which
areas have their own conventions. Work started before that is work done blind.

So the bundle ships **gated**, in two halves that do different jobs:

- **`CLAUDE.md` opens with a `## FIRST` section** telling Claude to say setup is pending and
  run `/setup` as its first action, above every other rule in the file. This is what makes
  setup *happen* — a hook can only refuse things, it can never make anything occur.
- **Two hooks make it unskippable**, for the case where that instruction is not followed —
  a fresh session opened with a concrete task is exactly when an instruction gets skipped.

The hooks key off marker files, giving three states:

| State | Bash | Edits | Meaning |
|---|---|---|---|
| `SETUP_REQUIRED` | read-only only (`ls`, `cat`, `grep`, read-only `git`, the setup's own scripts) | only setup's own files | nothing has started |
| `SETUP_IN_PROGRESS` | open | only setup's own files | `/setup` is running; verifying a test command means running it |
| neither | normal | normal | released; the hooks exit immediately and cost nothing |

Setup's own files are `CLAUDE.md`, `LESSONS.md`, `RUNBOOK.md`, `README.md`, `.gitignore`,
nested `CLAUDE.md`, and anything under `.claude/` or `scratch/`.

`/setup` reads the repo, interviews the user about what it couldn't determine, writes
`.claude/rules/project.md` (project facts, loaded every session — this is why `CLAUDE.md`
never needs project content), adds path-scoped rules for areas with their own conventions,
decides whether a `RUNBOOK.md` is warranted, **runs each command it writes down** to confirm it
works, and verifies the guards with `test_hooks.sh`. `.claude/setup/CHECKLIST.md` is the
definition of done.

Its last step runs `.claude/setup/release.sh`, which strips the `## FIRST` section from
`CLAUDE.md` and unwires both hooks from `settings.json` — parsed edits with assertions, not
hand edits, because a mangled `settings.json` silently disarms every other guard — then deletes
the markers, the hooks, the skill and itself, and re-runs the tests. The `CLAUDE.md` left
behind is byte-identical to the portable one in this repo; that is asserted by the test suite.

It gates the tools, not every shell trick. It exists to stop the agent plowing ahead, not to
defend against a determined bypass — which is why routing around it is a `CLAUDE.md` violation
rather than something engineered against.

## Correcting Claude

Two habits, both cheap:

- **Rewind, don't argue.** When a turn goes wrong, `/rewind` (or Esc Esc) restores the
  conversation and Claude's file edits to the checkpoint before it; then re-prompt with what
  you learned. "Try X instead" keeps the failed attempt in context, where it keeps steering
  the next one. Rewind does not undo what Bash did — a submitted job, a push, a delete — nor
  git state; the auto-commit history is the fallback for those.
- **Write it down, don't repeat it.** After a correction, "write that to `LESSONS.md`" (or
  "make that a skill") beats restating it next session. `CLAUDE.md` › Write it down tells
  Claude to do this unprompted; the prompt is for when it doesn't. In `hands-off/` the
  correction goes one level up — into the loop's prompt or skill (`CLAUDE.md` › Loops).

## Why it's built this way

- **Rules, mechanics, log — three files.** `CLAUDE.md` says how to act, and is the same
  on every machine for a given row. `RUNBOOK.md` says how to run things on *this* machine, and exists only where
  that's non-obvious (a cluster, a scheduler, a fragile env). `LESSONS.md` is the append-only
  log of corrections, imported into every session.
- **Anything that must happen every time is a hook, not a sentence.** `CLAUDE.md` is
  advisory — Claude Code's own guidance is to keep it short and put guardrails in hooks. So
  destructive git and `rm -rf` are denied by `PreToolUse` hooks, cleanup is enforced by a
  `Stop` gate that holds the turn open until every stray file is dealt with, and formatting
  runs after every edit. `test_hooks.sh` proves each guard against real bypass attempts.
- **`CLAUDE.md` stays under 150 lines**, each rule stated once, emphasis on almost nothing.
  Maintainer notes live in HTML comments (stripped before Claude sees them). Domain rules for
  data pipelines live in `.claude/rules/data-integrity.md` — delete that file where it
  doesn't apply.
- **Skills, not commands.** Workflows with side effects (`/commit-push-pr`, `/sbatch-run`)
  are `disable-model-invocation: true`: zero context cost until you type them, and Claude
  can't trigger them on its own. `/setup` is deliberately the exception — CLAUDE.md tells
  Claude to run it on the first turn, so Claude must be able to.

## What's in a bundle

```
CLAUDE.md                    hard constraints + how to work (≤150 lines)
LESSONS.md                   the log (imported via @LESSONS.md)
.gitignore                   ignores settings.local.json, CLAUDE.local.md, scratch/
.claude/
  settings.json              permissions + hook wiring
  settings.local.json.example
  rules/
    data-integrity.md        hard constraints for pipelines that read / detect / score
    project.md.template      the project-facts file /setup fills in and renames
  setup/                     deleted once /setup releases the gate
    SETUP_REQUIRED             the marker the two gate hooks key off
    CHECKLIST.md               what "set up correctly" means
    release.sh                 unwires the gate and deletes the setup machinery
  skills/
    setup/SKILL.md           /setup — the one-time guided setup (see The setup gate)
  agents/                    read-only review subagents — auditor, bug-hunter,
                             config-auditor, dead-code-finder, doc-auditor, verifier
  skills/
    commit-push-pr/SKILL.md  /commit-push-pr — stage, commit in repo style, push
    harness-docs/SKILL.md    /harness-docs   — re-read the Claude Code docs, report drift
  hooks/
    setup_gate.sh               SessionStart— announce that setup is pending
    block_until_setup.sh        PreToolUse  — deny source edits until /setup completes
    block_rm_rf.sh              PreToolUse  — deny recursive+force deletes and find -delete
    block_destructive_git.sh    PreToolUse  — deny reset --hard, clean -f, force-push,
                                              restore, --amend, rebase, stash drop, branch -D …
    ruff_format.sh              PostToolUse — ruff format + safe fixes on edited .py
    stop_untracked_gate.sh      Stop        — hold the turn open while untracked files remain
    stop_autocommit.sh          Stop        — commit tracked changes; push if CLAUDE_AUTO_PUSH=1
    audit_lessons.sh            Stop        — daily nudge (to Claude) on unreconciled lessons
    doc_check.sh                SessionStart— monthly nudge to run /harness-docs (and
                                              /niflheim-docs where that skill is installed)
    test_hooks.sh               probes every guard with real bypass attempts — run after copying
```

`hands-off/` changes or adds, in both columns:

```
CLAUDE.md                    decides and records instead of asking; nothing blocks on a human
.claude/
  settings.json              permissions.defaultMode: auto; env: CLAUDE_AUTO_PUSH=1 and
                             CLAUDE_VERIFY_CMD (empty — /setup fills it in)
  setup/CHECKLIST.md         adds: verify command set and seen to pass; one push succeeded
  hooks/
    stop_verify_gate.sh         Stop        — CLAUDE_VERIFY_CMD must pass before auto-commit;
                                              same failing diff is raised once, then the turn
                                              ends with nothing committed
  skills/
    maintain/SKILL.md        /maintain — one verified fix per iteration; /loop 1d /maintain
```

`niflheim/` adds:

```
RUNBOOK.md                   sbatch-only, partitions, uv/CUDA, the SSL bundle, ulimit -u,
                             root confinement, hook knobs + a project section to fill in
.claude/
  bin/
    loginpy                  bounded Python for a login node: every thread pool pinned to 1,
                             wall clock capped, refuses to start near the thread quota
  skills/
    sbatch-run/SKILL.md      /sbatch-run    — submit one job correctly, watch it in the background, act on the result
    root-lock/SKILL.md       /root-lock     — verify root confinement is actually in force
    niflheim-docs/SKILL.md   /niflheim-docs — re-read the cluster docs, report RUNBOOK drift
  hooks/
    node_facts.sh               SessionStart — hostname, CPU_ARCH, ulimit -u, thread use and
                                               this node's RUNBOOK table row, read live
    slurm_alloc.sh              SessionStart — run model + live partition state
    block_login_node.sh         PreToolUse   — deny unbounded Python on the login node
    block_outside_root.sh       PreToolUse   — deny any path outside ROOT
```

**Login-node Python** is bounded rather than banned. The binding limit on Niflheim is the
per-user thread cap (`ulimit -u`, which varies by node), and NumPy/PyTorch/MKL default to one
thread *per core* — so an uncapped `import torch` can want ~56 threads and `abort()` when a
fork fails.
`loginpy` pins every pool to 1 and caps the wall clock, which makes quick checks safe; the
guard still denies bare `python`, and scrubs only the allowed segment, so
`loginpy a.py; python b.py` is denied on the second half. Real work still goes through
`sbatch`.

## Migrating an existing project

`niflheim/MIGRATION.md` is a brief for the Claude session that does the move: copy the whole
`niflheim/` folder into the project, point Claude at that file, and it inventories the old
config, sorts the old `CLAUDE.md` line by line into rules / mechanics / project facts, carries
the lessons log over, installs, runs `test_hooks.sh`, and deletes itself. It is a one-time
document — not part of the installed bundle.

## Staying inside the project

On by default, nothing to install:

- **`block_outside_root.sh`** denies any path resolving outside `$CLAUDE_PROJECT_DIR` — literal,
  `~`, `~user`, `$HOME`, `$VAR/…`, `..` — and denies an argument to a path-taking command that
  it cannot resolve, so `H=$HOME; ls $H` and `cat "$SECRET"` do not get through. Allowed
  outside: `$HOME/.cache`, `$TMPDIR` / `/tmp`, read-only system prefixes, and anything in
  `$CLAUDE_ROOT_ALLOW`.
- **`permissions.deny`** blocks the file tools from credential paths (`~/.ssh`, `~/.aws`,
  `~/.gnupg`, `**/.env`), which the sandbox does not cover — Read, Edit and Write use the
  permission system, not the sandbox.
- **The Bash sandbox** runs shell commands in an OS jail (Seatbelt on macOS, bubblewrap on
  Linux). A read outside the project fails with `Operation not permitted`: no prompt, nothing
  to approve, no escape hatch (`allowUnsandboxedCommands: false`).

Linux needs `bubblewrap` and `socat` for the sandbox; where they are missing it stays off and
the hook does the work. `failIfUnavailable` is `false` so a missing dependency never blocks
anyone — the bundle works as shipped on any machine.

Be honest about the difference: with the sandbox, the kernel refuses. Without it, the hook is a
fence — it stops the obvious routes out, but a path computed inside a script (`bash walk.sh`)
is beyond what a lexical check can see. `/root-lock` reports which layer is actually in force.

**Not** `permissions.blockReadsOutsideWorkingDirectories`. It looks like the same thing, but
with it on Claude Code statically parses every Bash command, and anything the parser cannot
analyse — a `$VAR`, a quoted string, a heredoc, a `for` loop — becomes a permission prompt.
That is most real commands, and a flood of prompts teaches people to click through without
reading. A test asserts it stays out.

## Keeping it current

What counts as good practice here moves with each model generation — the Claude Code team
removed most of its own system prompt for the Claude 5 models and retired plan mode — and
every guide, this one included, dates. Sources, most authoritative first:

- **Official docs** — <https://code.claude.com/docs/en/best-practices>, and the
  [changelog](https://code.claude.com/docs/en/changelog) for what changed in the tool itself.
  The reference pages (hooks, settings, sub-agents, skills, scheduled tasks, checkpointing)
  are what the hooks and `settings.json` here depend on.
- **Anthropic engineering blog** — <https://www.anthropic.com/engineering>: the Claude Code
  best-practices article and the context-engineering posts explain *why* the docs say what
  they say.
- **The Claude Code team's own posts** — Boris Cherny (`@bcherny`) and Thariq Shihipar
  (`@trq212`) on X; dated and collected at <https://howborisusesclaudecode.com>. Primary
  sources for how the tool is meant to be used, but one team's workflow, not a standard.
- **Independent, dated commentary** — Simon Willison (<https://simonwillison.net/tags/claude-code/>)
  for a sceptical second opinion on each change.
- **The cluster docs** — <https://niflheim-users.readthedocs.io> for the Niflheim side.

`/harness-docs` does the check: it reads the first two, compares them with `CLAUDE.md`, the
hooks, skills, agents and `settings.json`, and reports where this harness has drifted — a
table and a proposed diff, no edits until you say so. It is deliberately **rare**: the
`SessionStart` hook (`doc_check.sh`) nudges once a month (`CLAUDE_DOCCHECK_DAYS`, `0` to
disable), the same cadence as the cluster-docs check. A harness that changes every week is
one nobody can learn; run it off-cycle when a new model generation ships, since that is when
the guidance actually moves.

## Deliberately not included

- `.mcp.json` — no project-scoped MCP servers.
- Output styles, statusline — defaults are fine.
