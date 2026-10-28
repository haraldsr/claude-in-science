---
name: harness-docs
description: Re-read the Claude Code best-practices guide and changelog and report where this harness has drifted from them
disable-model-invocation: true
allowed-tools: WebFetch, Read, Grep, Glob, Bash(date:*), Bash(mkdir:*), Bash(claude --version)
---

Check this harness — `CLAUDE.md`, `.claude/settings.json`, the hooks, skills and agents —
against current Claude Code guidance and report drift. **Report, then propose — do not edit
anything until the user says go.** Several sources, weighed by authority; one blog post is an
opinion, the docs are the contract.

1. Fetch, in this order:
   - <https://code.claude.com/docs/en/best-practices> — the official guide.
   - <https://code.claude.com/docs/en/changelog> — note the installed version
     (`claude --version`) and read every entry since it.
   - The reference pages the harness depends on: `hooks`, `settings`, `sub-agents`, `skills`,
     `scheduled-tasks`, `checkpointing`, `permission-modes` (same site, `/docs/en/<page>`).
   - <https://www.anthropic.com/engineering> — the Claude Code best-practices article and any
     context-engineering post newer than the last check.
2. For each claim this harness depends on, report `OK`, `CHANGED (was X, now Y)` or
   `COULD NOT VERIFY`, with the source URL:
   - **Hook events and their JSON** — `PreToolUse` `permissionDecision: deny`, `Stop` and
     `SessionStart` `additionalContext`, `matcher` syntax. A renamed field silently disarms a
     guard; this is the check that matters most.
   - **`settings.json` keys** used here: `permissions.allow/deny/defaultMode`, `sandbox`,
     `deniedMcpServers`, `attribution`, `env`.
   - **Skill and agent frontmatter**: `disable-model-invocation`, `allowed-tools`, `model`,
     `effort`, `tools`.
   - **CLAUDE.md guidance**: recommended length, rules versus judgement, what belongs in
     rules files and skills instead. If the guide now says less, name the lines here it would
     cut — do not propose adding.
   - **Loops, routines, auto mode**: `/loop` limits, where `/schedule` runs, what auto mode
     approves and flags.
3. Also report anything new that would do a job a hook or skill here does by hand. A built-in
   that makes one of ours redundant is the most valuable finding; a feature that is merely
   new is not a finding.
4. Output: one short table (claim → verdict → source), then the proposed edits as a diff.
   Where sources disagree, the docs win over the blog, and the blog over anyone's post; say
   which you followed.
5. Record the check so the reminder resets — write the stamp even when nothing changed,
   "verified unchanged" is a result:

       mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}" && date +%Y-%m-%d > "${XDG_CACHE_HOME:-$HOME/.cache}/claude_harness_doccheck"
