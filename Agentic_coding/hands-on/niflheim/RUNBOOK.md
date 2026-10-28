# RUNBOOK — DTU Niflheim

_How to actually run things on this cluster. Rules of conduct live in `CLAUDE.md`
(same file everywhere); this file is machine mechanics only. Project-specific
entrypoints, corpora and eval commands belong in the project's own section at the
bottom — keep the cluster part above it portable._

## The one rule: real compute goes through `sbatch`

Three limits are at work, and they are not the same thing. Knowing which one you are near is
the difference between a quick check and an hour of confusion.

- **Your thread quota is the one that actually bites.** The per-user thread cap (`ulimit -u`,
  varies by node) is shared with your editor's remote server. NumPy, PyTorch, MKL and
  OpenBLAS each default to ONE THREAD PER CORE, so a bare `import torch` plus one matmul on a
  56-core login node wants ~56 threads. When `pthread_create` then fails with EAGAIN, libgomp
  calls `abort()` — that is the SIGABRT that looks like it came from nowhere — and when the
  *shell* is what cannot fork, the Bash tool returns "Exit code 1" with no output. **Two
  symptoms, one cause.** Pinning every pool to one thread turns ~56 threads into ~5, which is
  the whole difference; `loginpy` does that for you.
- **The site kills long login-node processes**: 20 CPU-minutes, automatically, and the docs
  ask you not to monopolise a shared node. The nodes the table below lists without that
  limit are the documented home for long file transfers.
- **No login node has a GPU.** Anything touching CUDA goes to a compute node regardless of
  how small it is.

So: short, thread-capped checks belong on the login node through `loginpy`; a GPU, a real
dataset, or more than ~2 minutes belongs in `sbatch`. The guard hook denies bare `python`,
`pytest`, `pip`, `jupyter`, `torchrun` and `uv run|pip|sync`, including behind wrappers
(`timeout 60 python`, `nohup python`, `env X=1 python`, `bash -c "python …"`). It allows
`py_compile`, anything handed to `srun`/`sbatch`/`salloc`, `loginpy`, and an optional
per-project allowlist (see §Hook knobs). `bash foo.sh` is opaque to the guard — don't hide
Python in one.

- **Interactive `srun` does not work here.** Step-launch to GPU compute nodes fails from
  *every* login node (`svol`, `thul`, …): the login node can't resolve the compute-node
  name — `can't find address for host sNNN, check slurm.conf`. It's a site
  slurm.conf/DNS limitation, not a choice of login node, and `salloc --no-shell` fails
  the same way. **There is no persistent reusable allocation.** `sbatch` works fine: the
  batch script runs on the compute node.
- **Many items = ONE job.** Each process reloads its models (~10–30 s), so batch all
  items into a single job rather than submitting many small ones. A persistent
  allocation wouldn't help anyway — models reload per process regardless.
- **Submit, then watch in the background.** One watcher per job, started with
  `run_in_background` (or the Monitor tool), that exits when the job leaves the queue:

      until [ -z "$(squeue -h -j <JOBID>)" ]; do sleep 180; done
      sacct -j <JOBID> -X -n -o State,ExitCode,Elapsed

  When it fires, act on it: read the `--output` log with the Read tool, check the state, then
  fix and resubmit, start the next stage, or report. Each tick is a login-node process, so
  keep it light — interval ≥ 2 min, one Slurm call per tick, never a watcher per array task.

## Login nodes

**The login node is not fixed.** A session runs on whichever node it was started on, so
nothing in this file assumes one. At session start read `hostname`, `$CPU_ARCH` and
`ulimit -u` — `node_facts.sh` does this and hands you the result — and look that hostname up
in the table. What differs by node (the thread cap, whether the CPU-time limit applies, which
partitions it fronts) is never written into this file or `.claude/rules/` as a constant: the
last copy that did was wrong on the next node.

All are `<name>.fysik.dtu.dk`. Site-documented values, read 2026-09-21; live values win.

| Login node | Partitions it fronts | Cores / RAM | `CPU_ARCH` | CPU-time limit |
|---|---|---|---|---|
| `svol` | `xeon40el8`, `sm3090el8` | Skylake / 768 GB | `skylake_el8` | 20 min |
| `vid`, `thul` | `xeon40el9`, `sm3090el9` | Skylake / 384 GB | `skylake_el9` | 20 min |
| `slid` | `xeon24el9` | 24 / 256 GB | `broadwell_el9` | **none** |
| `sylg`, `slid2` | `xeon24el8` | 24 / 256 GB | `broadwell_el8` | **none** on `slid2` |
| `hrid` | `xeon56el9`, `a100el9` | 24 / 128 GB | `icelake_el9` | 20 min |
| `surt` | `xeon56`, `a100` | 56 / 512 GB | `icelake` | 20 min |
| `sara` | `xeon32el9`, `h200el9` | 32 / 512 GB | `sapphirerapids` | 20 min |
| `fjorm` | `epyc96` | 16 / 384 GB | `epyc9004_el9` | 20 min |

The pairing above is about *building* software — matching CPU architecture and OS — not about
submission; Slurm will normally accept a job for any partition from any login node. Confirm
once with `sinfo -p <partition>` from the node you intend to use before relying on it.

Two things follow from the node not being fixed:

- The node you are on fronts a few partitions; a job for any other is a **cross-partition
  submission**. That normally just works, but it is the reason to check a partition before
  using it for the first time (next section) rather than assuming.
- A venv is tied to the OS it was built on, and login nodes run both RockyLinux 8 and 9. The
  submit template already builds and runs inside the job on the compute node, which is what
  makes the login node's OS generation stop mattering — keep it that way rather than
  `uv sync`-ing on the login node and shipping the result to a job.

**Run the agent inside `tmux`.** Background watchers, `/loop` and everything else Claude Code
tracks live exactly as long as the `claude` process does, and a dropped SSH connection or a
closed laptop kills a bare one. `tmux new -s claude` once, `tmux attach -t claude` to come
back, and the session survives the disconnect. Only a node the table lists without the
CPU-time limit can host this: the others kill a user's processes once they accumulate 20
minutes of CPU time, which a long agent session can reach. The tmux server and its shell are
two more processes against the cap, so one session per project — not one per task.

## When a request can't be reached

Before submitting to a partition this project hasn't used before, check it actually exists,
admits the account, and can hold the ask:

```bash
showpartitions                                      # the site's own tool: every partition, live
sinfo -p <partition> -o '%P %a %l %D %t'            # exists / up / MaxTime / nodes / state
scontrol show partition <partition> | tr ' ' '\n' | grep -E 'AllowAccounts|MaxTime|State'
```

**`showpartitions` is the authority, not this table and not the website.** Partitions are added
and retired faster than either gets updated — see the note under Partitions.

Four distinct ways a request is unreachable, and they fail differently:

| What's wrong | How it shows |
|---|---|
| Partition doesn't exist | `sinfo` returns nothing for it |
| Exists, but the account isn't allowed | `AllowAccounts` excludes `catvip`; `sbatch` fails with *Invalid account or account/partition combination* |
| Exists, but every node is down/drained | `%t` is `down`/`drain`/`resv` — the job queues forever |
| The ask exceeds the partition | `--time` over the partition's `MaxTime`, or more GPUs than a node has |

**Flag it, never substitute.** If what the user asked for cannot be run, say exactly what is
unavailable and which of the four it is, offer the nearest reachable alternative, and wait for
an answer. Do not quietly downgrade the partition, the GPU count, the memory or the time limit
and then report the run as though it were the one that was requested: the numbers would be
attributed to hardware that never produced them, which is the same failure as reporting a
result you didn't verify. The same applies when a job is still pending for a reason —
`squeue -u $USER -o '%i %P %t %r'` prints the reason; `ReqNodeNotAvail` or `PartitionConfig`
means the request, not the queue, is the problem.

## Partitions and account

| Partition | Use | Notes |
|---|---|---|
| `sm3090el8` | Normal GPU runs | RTX 3090, 24 GB VRAM; nodes have 10 GPUs / 80 vcores, so request 8 cores per GPU |
| `xeon*` (CPU) | Anything not needing a GPU | Allocates much faster, but **no `libGL`** — a GUI-linked `cv2` build fails to import there |

Default max time is 50 h in all partitions; some accept up to 168 h. `showpartitions` gives the
real values.

> **`sm3090_devel` is gone.** It was the quick-debug GPU partition here and no longer exists on
> the cluster — but the website still documents it (as a 1-node, 10-minute partition). If you
> find it mentioned anywhere, that is stale, not a partition to go back to. For a short debug
> run, submit to `sm3090el8` with a small `--time`; the scheduler favours short jobs. The site
> also lists `xeon24el9_test`, a 10-minute CPU partition for development tests only.
>
> This is why `showpartitions` beats any written list, this file included: the docs lagged the
> cluster, and so did this runbook.

GPU access is authorized for account `catvip`.

Newer GPU partitions exist on the cluster — `sm3090el9` (via `vid`/`thul`), `a100` / `a100el9`
(`surt` / `hrid`) and `h200el9` (`sara`). This file assumes `sm3090el8` because that is what
has been used, not because it is the best available. If the account can reach an A100 or H200
that is a large step up; `sinfo -p a100el9,h200el9` from the matching login node settles it.

## Environment: uv + Python 3.12.9

The module system ships only Python 3.11.3 / 3.13.5 and has **no CUDA module**, so do
**not** `module load Python` — use uv and let PyTorch's wheels provide CUDA. Run code as
`uv run python …`. **GPAW is the exception** and does come from a module — see § GPAW and ASE.

A `.venv/` synced from another machine has a dangling Python symlink: rebuild with
`uv sync`, inside an `sbatch` job so it builds on the compute node.

Scripts must live under `$HOME` (NFS, shared across nodes). `/tmp` is node-local and
invisible to the job.

## GPAW and ASE

**The uv rule above does not apply to GPAW.** GPAW is an EasyBuild module here, and loading it
pulls in Python, ASE and matplotlib at matching versions; installing it through uv/pip means
compiling C against libxc, BLAS and MPI by hand. ASE on its own is pure Python and works
either way — but when GPAW is in the picture, take ASE from the GPAW module so the versions
agree.

```bash
module purge
module avail GPAW                 # authoritative — never take a version from this file
module load GPAW/<version>-<toolchain>
module list                       # every loaded module must share ONE toolchain
```

Naming is `GPAW/<ver>-<toolchain>[-ASE-<ver>][-CUDA-<ver>]`; newer modules drop the ASE
suffix. Mixing toolchains (`intel-2025b` alongside `foss-2025b`) crashes at import or, worse,
at runtime.

Module trees are per-`CPU_ARCH` — see the login-node table above. The submit script below
loads the module inside the job, so the job sees the tree for the partition's own
architecture; what `module avail GPAW` shows on the login node is that node's tree. A version
name that worked in a job on one architecture need not exist on another, in either direction
— so `module avail` on the node you are on before a login-node check, and `--dry-run` before
trusting a version name for a partition you have not used it on.

### Submitting

GPAW is MPI. Ask for tasks (`-N` / `-n`), not cores-per-task (`-c`), and pin
`OMP_NUM_THREADS=1` unless you are deliberately running hybrid.

```bash
#!/bin/bash -l
#SBATCH --partition=xeon24el8
#SBATCH --account=catvip
#SBATCH -N 1 -n 24
#SBATCH --time=2:00:00
#SBATCH --output=$HOME/.cache/run-%j.log
module purge
module load GPAW/<version>-<toolchain>
export OMP_NUM_THREADS=1
cd "$PROJECT"
mpiexec -n $SLURM_NTASKS gpaw python script.py
```

**Use a script file, not `--wrap`.** `module` is an Lmod shell function and `--wrap` generates
a plain `#!/bin/sh` job script where it is not necessarily defined — which is why the template
in the next section does not carry over to GPAW. The `-l` in `#!/bin/bash -l` is what makes
`module` available. Confirm this once on the cluster rather than trusting either reading.

`mpiexec -n … gpaw python script.py`, never `gpaw-python` — that spelling is retired. The
`SSL_CERT_FILE` / certifi line is a no-op here: GPAW downloads no models. What it does need is
PAW setups — `gpaw info` prints the search path and whether they were found.

Size the job before spending it: `gpaw python --dry-run=8 script.py` prints the
parallelisation scheme and the RAM per process without running anything. Tune through the
calculator's `parallel={...}` dict — `kpt`, `domain`, `band`, `sl_auto`, `use_elpa`.

### On a login node

The guard denies `gpaw`, `ase`, `mpiexec` and `mpirun` at command position, because they start
Python without the word ever appearing — `gpaw python x.py` is `python -m gpaw`. There is no
`.venv` with a module-based GPAW, so `loginpy` needs pointing at the module's interpreter.
The tree it loads from is this login node's `CPU_ARCH`, so `module avail GPAW` first — the
version the job used was checked for the compute node's architecture, not this one's:

```bash
module avail GPAW
module load GPAW/<version>-<toolchain>
LOGINPY_PYTHON=$(command -v python3) bash .claude/bin/loginpy -m gpaw info
```

### GPU

GPAW's GPU backend is **A100 only** — `a100` / `a100el9`, fronted by `surt` / `hrid`, with a
`-CUDA-` module visible only from those login nodes. `sm3090el8`, the default everywhere else
in this file, is not a GPAW GPU target. Enable with `parallel={'gpu': True}` or
`export GPAW_USE_GPUS=1`, and request one core per GPU.

Sources: <https://gpaw.readthedocs.io/platforms/Linux/Niflheim/load.html>,
<https://gpaw.readthedocs.io/platforms/Linux/Niflheim/gpu.html>,
<https://gpaw.readthedocs.io/documentation/parallel_runs/parallel_runs.html>.
Read 2026-09-22, not verified against this cluster — `module avail GPAW` settles any conflict.

## The submit template

```bash
sbatch --partition=sm3090el8 --account=catvip --gres=gpu:1 -c 8 -N1 --time=0:30:00 \
  --output=$HOME/.cache/run-%j.log \
  --wrap='cd "$PROJECT" && export SSL_CERT_FILE=$(.venv/bin/python -c "import certifi;print(certifi.where())") && uv run python <entrypoint> <args>'
# prints "Submitted batch job <jobid>"; when it finishes:
cat $HOME/.cache/run-<jobid>.log
```

`/sbatch-run <command>` does this for you and then stops. It does not fit GPAW — that needs a
script file rather than `--wrap`, and MPI tasks rather than `-c`; see § GPAW and ASE.

**What the SSL line is for.** On first use, model downloads go over HTTPS, and Python
only accepts an HTTPS connection if it can check the server's certificate against a
trusted CA bundle. On Niflheim's compute nodes Python can't find the system copy, so
every download fails with `SSL: CERTIFICATE_VERIFY_FAILED`. The `certifi` package ships
its own bundle inside the venv: the inner `$(…)` asks the venv's Python where that file
is, and `export SSL_CERT_FILE=…` points Python's HTTPS machinery at it. Once models are
cached the line is a harmless no-op — which is why it's always included rather than
reasoned about. Some libraries read `REQUESTS_CA_BUNDLE` instead; export both:

```bash
export SSL_CERT_FILE=$(.venv/bin/python -c 'import certifi;print(certifi.where())')
export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"
```

## Quick checks on a login node

`bash .claude/bin/loginpy <args>` is the bounded way to run Python here: every thread pool pinned
to 1, a 120 s wall clock, and a pre-flight refusal when your thread quota is already 80 %
spent — so an over-reach arrives as a sentence instead of a silent exit 1. The pre-flight
reads the live `ulimit -u`, so it adapts to whatever node you are on. A longer
`LOGINPY_TIMEOUT` is safe only on a node the table lists without the CPU-time limit.

```bash
uv run python -m py_compile <edited files>        # unwrapped: parses, imports nothing
bash .claude/bin/loginpy -c 'import torch; print(torch.__version__, torch.cuda.is_available())'
bash .claude/bin/loginpy src/entry.py --help
```

Always `py_compile` edited files before submitting, so a typo doesn't waste a GPU job.

**Fine through `loginpy`**: import checks, `--help` and argparse validation, reading a
checkpoint's keys or a model config, parsing a handful of rows, a unit test that stays off the
heavy stack.

**Still `sbatch` regardless**: anything needing a GPU; a real dataset; multiprocessing or
DataLoader workers (each worker spawns its own pool, straight back into the cap); anything
over ~2 minutes; and `uv sync` / `pip install` when a wheel builds from source, since
`make -j$(nproc)` is both a thread bomb and easily past 20 CPU-minutes — do those in a job, or
on a node the table lists without the CPU-time limit, after checking `ulimit -u` has room.

`loginpy` is not a loophole. The guard scrubs only the `loginpy` segment before checking what
is left, so `loginpy a.py; python b.py` is still denied.

## When the Bash tool dies for no reason

The agent shares the login node's per-user limits with everything else you have open
there. The one that bites is the **process/thread cap** (`ulimit -u`, varies by node): if
it's mostly consumed, a command that needs to `fork()` fails with EAGAIN and the tool returns
a clean **"Exit code 1" with no output**. It is not a time-based usage governor.

Same cause, different victim: when it's a *thread pool* rather than the shell that can't fork,
libgomp calls `abort()` and you get a SIGABRT mid-import instead. If an old crash log says
`Thread creation failed` or `Resource temporarily unavailable`, that was this, not the login
node objecting to Python as such. `loginpy` avoids both by pinning the pools to one thread.

```bash
ulimit -u; ulimit -Hu                                  # soft and hard caps
ps -u $USER -o nlwp= | awk '{s+=$1} END{print s}'      # threads currently used
ps -u $USER -o nlwp,comm --sort=-nlwp | head           # the hogs
```

- The soft limit can usually be raised up to the hard cap yourself: `ulimit -u <hard>`.
- The biggest consumer is typically an **IDE remote server and its language extensions**.
  Running the agent from a plain terminal frees the most headroom.
- Prefer **Read / Edit / Write** over `cat` / `grep` for file work — those tools never
  spawn a login shell and keep working while Bash is locked out.
- Keep login-shell spawns low: one submit, one background watcher per job ticking every few
  minutes. That is two processes at a time; a tight loop or a watcher per item is not.
- **When the shell breaks, stop and wait.** Stop the watchers (TaskStop), no auto-retry
  loop, nothing left running on the login node during the outage — that only prolongs it.
  Resume with single, spaced commands once it's back, then restart one watcher per live job.
- A subagent also runs Bash on the login node, so it does **not** raise the ceiling.

## Before editing code

`squeue -u $USER` is a precondition for editing any module a running job will still
import — long eval/gate jobs run out of the LIVE working tree for hours. Check what's
unfamiliar with `scontrol show job <id> | grep Command`. Pin long comparison harnesses
to a detached `git worktree` at a fixed commit instead of the live tree.

## Root confinement

Root confinement is not cluster-specific — it ships in both bundles and the README covers
it. What matters here: `block_outside_root.sh` denies any tool call whose path resolves outside
`$CLAUDE_PROJECT_DIR` — absolute, `~`, `~user`, `$HOME`, `$VAR/…` and `..` tokens alike —
(`permissions.blockReadsOutsideWorkingDirectories` is deliberately NOT set — it turns every
Bash command the shell parser cannot analyse into a permission prompt). On a shared cluster, `$HOME` and the group filesystem hold other projects and
other people's data, and a recursive walk out there is slow on NFS as well as a privacy
problem.

Allowed outside ROOT: `$HOME/.cache` (job logs), `$TMPDIR` / `/tmp`, read-only system
prefixes, and anything in `$CLAUDE_ROOT_ALLOW`. Run `/root-lock` to verify the guard is
wired and to live-test it; `bash .claude/hooks/test_hooks.sh` probes it (and every other
guard) with real bypass attempts. Known limits of a lexical check: a variable that already
holds a path (`H=$HOME; ls $H`) and a script that does the walking (`bash walk.sh`).

## How confinement actually works

Two layers, both on by default, neither needing anything installed:

- **`block_outside_root.sh`** denies any path outside the project — literal, `~`, `~user`,
  `$HOME`, `..`, and any argument to a path-taking command that cannot be resolved, so
  `H=$HOME; ls $H` and `cat "$SECRET"` are denied rather than waved through. The built-in file
  tools (Read, Edit, Write) never reach the sandbox below, so this is what covers them.
- **The Bash sandbox** (`sandbox.enabled`) puts shell commands in an OS jail where a read
  outside the project fails with `Operation not permitted` — no prompt, nothing to approve.

The sandbox needs `bubblewrap` and `socat` on Linux. The login nodes have bubblewrap but not
socat (`command -v socat` settles it for the one you are on), so it sits idle and the hook
does the work. `failIfUnavailable` is `false` on purpose: a missing dependency must never
stop you working. macOS needs nothing.

**Optional, if you want the hard guarantee:** put `socat` on `PATH` — `module avail socat`, a
conda env, or unpacking the Rocky 8 RPM into `~/.local` — restart, and `/sandbox` will show it
active. Nothing else to change. Without it you still have the hook, which is a fence rather
than a wall: a path computed inside a script (`bash walk.sh`) is beyond what any lexical check
can see.

## Hook knobs

| Variable | Hook | Effect |
|---|---|---|
| `CLAUDE_LOGIN_SAFE_RE` | `block_login_node.sh` | Regex of VERIFIED stdlib-only scripts allowed to run on the login node. Unset ⇒ no exemptions. Verify *transitive* imports first; one transitive `torch` import SIGABRTs the node. |
| `CLAUDE_LOGIN_HEAVY_RE` | `block_login_node.sh` | Regex of scripts that must never run there; overrides the safe list. |
| `CLAUDE_ROOT_ALLOW` | `block_outside_root.sh` | Extra colon-separated prefixes allowed outside ROOT. Set it in `settings.json`, not ad hoc mid-task. |
| `CLAUDE_AUTO_PUSH` | `stop_autocommit.sh` | `1` pushes after each auto-commit. Off by default; personal, so it goes in `settings.local.json`. |
| `LOGINPY_TIMEOUT` | `loginpy` | Wall-clock seconds before SIGTERM. Default 120. Raise it only on a node the table lists without the CPU-time limit — and you are drifting toward work that belongs in a job. |
| `LOGINPY_THREADS` | `loginpy` | Value for every `*_NUM_THREADS`. Default 1. Raise it only on a node the table lists without the CPU-time limit, and only knowing the live cap (`ulimit -u`). |
| `LOGINPY_PYTHON` | `loginpy` | Interpreter override. Default `./.venv/bin/python`, else `uv run python`. |
| `CLAUDE_DOCCHECK_DAYS` | `doc_check.sh` | Days between documentation-drift reminders. Default 30; `7` for weekly, `0` to disable. |

## Skills

All of these are `disable-model-invocation: true` — only you can trigger them, and they cost
no context until you do. (`/setup`, which ships only until setup completes, is the one
exception: CLAUDE.md tells Claude to run it on the first turn, so Claude has to be able to.)

| Skill | Does |
|---|---|
| `/sbatch-run <cmd>` | py_compile, pick a partition, submit one job from the template above, report the jobid, stop |
| `/root-lock` | Verify root confinement is wired and live-test it |
| `/niflheim-docs` | Re-read the cluster docs and report where this file has drifted from them |
| `/commit-push-pr` | Stage, commit in repo style, push to origin |

## Keeping this file honest

The cluster moves under you: partitions are added and retired, OSes get bumped, limits change.
A `SessionStart` hook reads a stamp file and, once every 30 days (`CLAUDE_DOCCHECK_DAYS`),
asks for `/niflheim-docs` — which re-reads <https://niflheim-users.readthedocs.io>, checks the
specific claims this file depends on, reports drift as a table plus a proposed diff, and
writes the stamp. It costs nothing on the sessions in between: no network, just a file date.

Monthly, because what changes here changes on the order of months; weekly would mostly produce
"no change" turns and teach everyone to ignore the nudge. Run it early instead of waiting for
the reminder after a cluster announcement, an OS upgrade, or any "that used to work" moment.

---

## Project section

_Add the project's own entrypoints, corpora, regression cases and eval commands here.
Keep them below this line so everything above stays copyable to the next project on
this cluster. Not the login node: `node_facts.sh` reads it live every session, and a node
written here is wrong the next time the session starts somewhere else._
