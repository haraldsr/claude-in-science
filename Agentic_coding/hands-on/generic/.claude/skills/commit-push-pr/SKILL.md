---
name: commit-push-pr
description: Stage all changes, commit in the repo's style, and push the current branch to origin
disable-model-invocation: true
argument-hint: [optional commit message]
allowed-tools: Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git add:*), Bash(git commit:*), Bash(git push origin HEAD), Bash(git rev-parse:*), Bash(git symbolic-ref:*), Bash(git branch:*)
---

Commit the working tree and push it to `origin` (see CLAUDE.md › Git).

Steps:

1. `git status --porcelain` and `git diff HEAD --stat`. If there is nothing to commit, say so and stop.
2. Show the user what will be committed (status + short diffstat).
3. Confirm the branch: `git rev-parse --abbrev-ref HEAD`. This is meant to run on `main`. If the branch is NOT `main`, say which branch you're about to push and ask the user to confirm before continuing.
4. Stage everything: `git add -A`.
5. Commit subject: if `$ARGUMENTS` is non-empty, use it verbatim. Otherwise write ONE concise subject (<70 chars) matching the style of `git log -10 --pretty=%s` — no trailing punctuation, no "commit:" prefix. Use a HEREDOC if a body is genuinely warranted. Do NOT add a Claude co-author trailer — commits in this repo are attributed to the user only.
6. Push:

       git push origin HEAD

7. Report the commit hash, the branch, and the push result.
8. If the push is rejected (e.g. non-fast-forward), STOP and show the error. Do NOT `--force` and do NOT `git pull --rebase` — `block_destructive_git.sh` blocks both anyway, and a non-fast-forward on a repo shared with another machine needs diagnosis, not a blind pull.

Never rewrite history. Never push any branch other than the current one.
