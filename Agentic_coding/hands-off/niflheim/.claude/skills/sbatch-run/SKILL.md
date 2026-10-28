---
name: sbatch-run
description: Submit a command to Slurm the correct way for this cluster — one job, a background watcher, then act on the result
disable-model-invocation: true
argument-hint: <command to run on the compute node>
allowed-tools: Bash(sbatch:*), Bash(squeue:*), Bash(sacct:*), Bash(sleep:*), Bash(sinfo:*), Bash(scontrol show partition:*), Bash(uv run python -m py_compile:*), Read, Monitor, TaskStop
---

Run `$ARGUMENTS` on a compute node. Never on the login node, never via `srun`/`salloc`
(step-launch to GPU nodes is broken here — see RUNBOOK.md).

1. If the command invokes a Python entrypoint, syntax-check it first (allowed on the login
   node): `uv run python -m py_compile <entrypoint>`. Stop on failure.
2. Pick the partition: `sm3090el8` for GPU work, with a small `--time` for a quick debug run
   (the scheduler favours short jobs). A CPU partition only if nothing needs a GPU and nothing
   imports a GUI-linked `cv2`. `sm3090_devel` no longer exists — do not use it, whatever any
   older note or the website says.
3. **If the user named a partition or resource this project hasn't used before, verify it is
   reachable before submitting** (RUNBOOK.md › When a request can't be reached):

       sinfo -p <partition> -o '%P %a %l %D %t'
       scontrol show partition <partition> | tr ' ' '\n' | grep -E 'AllowAccounts|MaxTime|State'

   Unreachable — absent, account not in `AllowAccounts`, every node down/drained, or the ask
   over `MaxTime` or the node's GPU count — means **STOP and tell the user which of those it
   is**, with the nearest reachable alternative. Never silently fall back to another partition
   or a smaller ask and report the run as the one they asked for.
4. Submit ONE job using the template in RUNBOOK.md › "The submit template" — verbatim
   (account, `--output=$HOME/.cache/run-%j.log`, the SSL line), substituting the partition,
   a time limit, and the command. Batch everything into that one job rather than submitting
   many small ones: models reload per process.
5. Report the JOBID and the log path, then start ONE background watcher for it
   (`run_in_background: true`), as in RUNBOOK.md › "Submit, then watch in the background":

       until [ -z "$(squeue -h -j <JOBID>)" ]; do sleep 180; done
       sacct -j <JOBID> -X -n -o State,ExitCode,Elapsed

   Interval ≥ 2 min and one Slurm call per tick — each tick is a login-node process. Never
   a foreground `sleep` or a tight loop.
6. When the watcher fires, read `$HOME/.cache/run-<jobid>.log` with the Read tool and act on
   the outcome: on success, verify the output and continue with whatever the task needs
   next; on failure, diagnose, fix and resubmit through this skill. Report what happened.
