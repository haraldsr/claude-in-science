# LESSONS

The running log for **this** project: what went wrong, and the rule that came out of it.
Rules of conduct live in `CLAUDE.md`; machine mechanics live in `RUNBOOK.md` (where one
exists). `CLAUDE.md` imports this file, so it is in context every session.

**Append to it after any correction.**

Format — one line per lesson:

```
- <what went wrong> → <the rule that prevents it>
```

Conventions:

- **Append-only.** Don't rewrite or delete an entry once it's resolved; append
  ` [DONE — how]` to it. The history is the point.
- **One lesson, one line.** If it needs a paragraph, the rule isn't sharp enough yet.
- A lesson that keeps recurring has outgrown this file — promote it to a hard constraint
  in `CLAUDE.md` and leave the entry here pointing at it.
- Keep entries specific enough to act on: the actual symptom, then the actual rule.
  "Be more careful" is not a lesson.
- Machine mechanics — partitions, schedulers, login-node names, job templates — belong
  in `RUNBOOK.md`, not here.
- This file is loaded whole every session, so keep it short. Past ~60 lines, move `[DONE]`
  entries to `LESSONS-archive.md` (kept in the repo, not imported). Moving is not deleting.

---

## Lessons

_Empty. First entry goes here._
