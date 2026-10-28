---
name: setup
description: One-time guided setup — lay out this project's context, verify the guards, then remove the gate
allowed-tools: Read, Grep, Glob, Edit, Write, AskUserQuestion, Bash(git:*), Bash(ls:*), Bash(cat:*), Bash(find:*), Bash(command -v:*), Bash(bash .claude/hooks/test_hooks.sh), Bash(.claude/setup/release.sh)
---

Set this project up so the harness has something to work with, then release the gate. Work
through `.claude/setup/CHECKLIST.md` — read it first; it is the definition of done.

**Interview the user rather than guessing.** Use `AskUserQuestion`. You can read the repo to
propose answers, but a wrong build command written down confidently is worse than an empty
field, because everything downstream treats it as true.

## 0. Is this the right place?

Before anything else, check that this directory is one project and the project the user means.
Getting this wrong writes a project's context into the wrong place, which is worse than not
setting up at all. Signals that something is off:

- it looks like a home, `Downloads` or `Desktop` folder rather than a project;
- several independent projects sit side by side — more than one `package.json`,
  `pyproject.toml`, `Cargo.toml`, `go.mod`, or nested repositories in subdirectories;
- there is no recognisable project here at all: no manifest, no source directory;
- the real root looks like it is *above* here, so the harness landed in a subfolder.

If any of that holds, **stop and ask the user** which directory this should be set up for, and
whether the harness should be moved there — do not guess, and do not set up a folder full of
unrelated projects as though it were one. Ask about anything else you are unsure of, too: a
question now costs one turn, a wrong assumption costs the whole setup.

## 1. Mark setup as started

Write `.claude/setup/SETUP_IN_PROGRESS` (copy `SETUP_IN_PROGRESS.template`). Until it
exists the gate holds Bash to read-only inspection; with it, shell commands run, because
step 5 has to actually execute the commands it records. Source files stay gated either way.

## 2. Look before asking

Explore the repo and form a draft: languages, layout, entrypoints, test framework, CI config,
existing `README`/`AGENTS.md`/`.cursorrules`, package manifests, lockfiles, git remote. Use a
subagent if it spans many files. Report what you found in a few lines.

## 3. Interview

Ask about what you could not determine, and confirm what you inferred: what the project is
for; which directories matter and which are noise; the build, test and lint commands; anything
non-obvious that a newcomer gets wrong. Don't ask what the repo already answers.

Then put **every optional piece of context to the user as a choice**, with your recommendation
and the reason for it. These are not yours to settle quietly — a setup that silently decides
half of itself leaves the user with a config they did not choose and cannot see:

| Ask | Recommend based on |
|---|---|
| Per-area context: a `CLAUDE.md` inside `src/`, `tests/` and any other code directory. Name the directories you propose, and let them say yes, no, or pick a subset | default to proposing every code directory. They cost nothing until Claude reads a file there, and a small directory still benefits from one line on what it holds and what not to break |
| A `RUNBOOK.md` | whether running things here is non-obvious: a cluster, a scheduler, a fragile env |
| Keeping `.claude/rules/data-integrity.md` | whether this project reads, detects or scores values |
| Auto-push (`CLAUDE_AUTO_PUSH=1`) | off unless the user wants every turn pushed |

Use `AskUserQuestion` so each is one click, and say plainly what you would do and why. "I don't
think this project needs X" is a recommendation to put to them, never a conclusion to act on
alone. If the tool is unavailable, ask in plain text and wait — do not proceed on your own
answer.

## 4. Write the context files

Write these in order, and **state the path after each one**. This list is mechanical: the
decisions were made in step 3, so do not re-litigate them here. "This directory is too small to
need one" is a step 3 conversation, not a step 4 judgement call.

1. `.claude/rules/project.md` — always. The project facts, loaded every session alongside
   `CLAUDE.md`. Under ~60 lines, concrete: commands, paths, gotchas. No philosophy, no
   restating `CLAUDE.md`.
2. **A `CLAUDE.md` inside every code directory the user agreed to** — normally `src/` (or the
   equivalent) and `tests/`. Start from `.claude/setup/dir-CLAUDE.md.template`. Write it even
   for a small directory: what lives there, the public surface, and what a change there must
   not break. A directory with genuinely nothing special still gets the file, saying what it
   holds and that it follows the top-level conventions — a present file records that the
   question was settled, a missing one looks like an oversight. These load only when Claude
   reads a file in that directory, so they cost nothing the rest of the time.
   Skip this step **only** if the user declined per-area context outright in step 3.
3. `.claude/rules/<area>.md` with `paths:` frontmatter — instead of a nested `CLAUDE.md` where
   the area is a file pattern rather than a directory (`**/*.test.ts`, every migration file).
- `RUNBOOK.md` — only if the user agreed one is warranted. Fill in its project section.
5. Delete `.claude/rules/data-integrity.md` if the user said it does not apply.

**Nothing project-specific goes into `CLAUDE.md`.** It is the portable contract and stays
byte-identical across projects; that is what `.claude/rules/` and directory `CLAUDE.md` files
are for.

## 5. Verify — this is the part that matters

- **`ls` every file step 4 was supposed to produce** and show the result. A file you agreed to
  write and did not is a failed setup, not a footnote — if it is missing, write it now.
- Run each command you wrote down, once. Report the actual output. A command that does not
  run gets fixed or removed, not written down hopefully.
- `command -v jq` — without it every guard fails closed.
- `bash .claude/hooks/test_hooks.sh` — every line must PASS. If any fails, **stop**: report it
  and do not release the gate. The rules in `CLAUDE.md` assume these guards work.
- Confirm `.gitignore` covers `scratch/`, `.claude/settings.local.json`, `CLAUDE.local.md`.
- Ask whether auto-push should be on (`CLAUDE_AUTO_PUSH=1` in `.claude/settings.local.json`);
  default is off.

## 6. Release

Show the user the completed checklist, **every file you created with its path**, and —
explicitly — **what you did not create and why**, so anything you talked yourself out of is visible and reversible in one
sentence. Then ask for a yes and run:

    .claude/setup/release.sh

It unwires the two setup hooks from `settings.json` (a parsed edit with assertions, not a
hand edit), deletes them along with this skill and `.claude/setup/`, and re-runs the hook
tests. Confirm its output, then `git add` the new files and commit — this is one commit.

Finally, tell the user to run `/context` and check that `CLAUDE.md` and `.claude/rules/` appear
under **Memory files**. A file that is not listed there was not loaded, and writing it achieved
nothing.

## If setup cannot complete

Say which checklist line is blocked and why, and stop. Do not delete the marker to get moving,
do not loosen a hook, and do not write a command you have not run. An unfinished setup that is
honest about it is fine; a released gate over a broken one is not.
