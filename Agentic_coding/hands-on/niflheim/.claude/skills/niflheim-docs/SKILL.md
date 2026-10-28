---
name: niflheim-docs
description: Re-read the Niflheim documentation and report where RUNBOOK.md has drifted from it
disable-model-invocation: true
allowed-tools: WebFetch, Read, Bash(date:*), Bash(mkdir:*), Bash(sinfo:*), Bash(squeue:*)
---

Check `RUNBOOK.md` against the live cluster documentation at
<https://niflheim-users.readthedocs.io/en/latest/index.html> and report drift. **Report, then
propose — do not edit `RUNBOOK.md` until the user says go.**

1. Fetch the documentation index, then the Getting Started page and whatever it links for
   partitions/hardware and the batch system. Prefer the site's own pages over search results.
2. Check each claim below — these are the ones `RUNBOOK.md` actually depends on. For each,
   report `OK`, `CHANGED (was X, now Y)`, or `COULD NOT VERIFY`:
   - **Login nodes**: the node → partition mapping, core counts, RAM, `CPU_ARCH` strings, and
     which nodes have no CPU-time limit.
   - **The CPU-time limit** on login nodes (RUNBOOK says 20 minutes, auto-killed; the table
     says which nodes are exempt) and the per-user thread cap (`ulimit -u`, varies by node).
     RUNBOOK deliberately records no number for the cap — the live value on the node you are
     on is the one that counts, so do not propose writing one in.
   - **Partitions**: run `showpartitions` on the cluster — it is authoritative and beats both
     this runbook and the website, which have each been wrong. Check `sm3090el8` still exists,
     whether `xeon*` still lack `libGL`, and which GPU partitions the account can now reach
     (`sm3090el9`, `a100`, `a100el9`, `h200el9` …). Note that the website still documents
     `sm3090_devel`, which is retired: where the site and `showpartitions` disagree, the
     cluster wins, and say so in the report.
   - **Interactive jobs**: is `srun`/`salloc` step-launch to compute nodes still impossible
     from login nodes? If the site has fixed this, say so loudly — it would change how the
     whole project runs, and RUNBOOK's central claim would be wrong.
   - **Python / toolchain**: which Python versions the module system ships, whether a CUDA
     module now exists, and whether the `uv` advice still holds.
3. Also report anything *new* that would matter here: a faster GPU partition the account can
   reach, a changed submit requirement, a new storage or quota rule.
4. Output: one short table (claim → verdict → source URL), then the proposed `RUNBOOK.md`
   edits as a diff — including the `read <date>` label on the login-node table, which moves
   to today whenever the table was checked, changed or not. Nothing project-specific goes
   anywhere near `CLAUDE.md`, and no login node becomes "the one this project uses".
5. After reporting, record the check so the reminder resets:

       mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}" && date +%Y-%m-%d > "${XDG_CACHE_HOME:-$HOME/.cache}/claude_niflheim_doccheck"

   Write the stamp even when nothing changed — "verified unchanged" is the result.
