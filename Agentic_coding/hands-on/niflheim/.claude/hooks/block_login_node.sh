#!/usr/bin/env bash
# PreToolUse hook: block ALL Python / compute execution on the login node.
#
# Standing rule (reaffirmed after repeated SIGABRT crashes): the login node must NEVER run
# compute — not the pipeline, and not even a CPU-only diagnostic that imports
# torch/cv2/easyocr/paddleocr. Any Python work goes through Slurm (sbatch) so it executes on
# a compute node.
#
# Denies ANY Python invocation at command position — python/pytest/pip/jupyter/torchrun/…,
# `uv run|pip|sync|tool`, `poetry|conda|mamba|pipx run`, and the launchers that start Python
# without naming it (`gpaw`, `ase`, `mpiexec`, `mpirun`) — including behind wrappers
# (timeout 60 python …, nohup python …, env X=1 python …, bash -c "python …").
# Allowed: anything handed to srun/sbatch/salloc (it runs ON the compute node), a pure
# `py_compile` syntax check (imports nothing), `.claude/bin/loginpy` (the bounded wrapper —
# thread pools pinned to 1, wall clock capped; see RUNBOOK.md › Quick checks on a login node),
# and an optional per-project allowlist.
# Allowed segments are SCRUBBED before the check, so `loginpy a.py; python b.py` and
# `python x.py && sbatch y.sh` are still denied on the un-scrubbed half.
# Known limit: `bash run.sh` is opaque — a script that calls python is not seen.
# Fail CLOSED: if jq is missing, deny. Probe it with test_hooks.sh.
set -u
if ! command -v jq >/dev/null 2>&1; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"jq missing from PATH — the login-node guard cannot parse the command, so blocking for safety (fail-closed). Install jq to ~/.local/bin or run via sbatch."}}'
  exit 0
fi
cmd=$(jq -r '.tool_input.command // ""')

# Allow static syntax checks anywhere (py_compile parses, imports nothing).
if echo "$cmd" | grep -q 'py_compile'; then exit 0; fi

# Scrub the parts of the command that are legitimately allowed, then check what is LEFT.
# - srun/sbatch/salloc: everything after them IS the job and runs on a compute node. Their
#   arguments routinely contain `&&` inside --wrap='...', so scrub to end of line.
# - loginpy: bounded by construction; scrub only its own segment.
scrubbed=$(printf '%s\n' "$cmd" \
  | sed -E 's#(^|[;&|(])[[:space:]]*([^[:space:];&|`)(]*/)?(srun|sbatch|salloc)[[:space:]].*$#\1 :#' \
  | sed -E 's#(^|[;&|(])[[:space:]]*(bash[[:space:]]+|sh[[:space:]]+)?([^[:space:];&|`)(]*/)?loginpy([[:space:]][^;&|`)]*)?#\1 :#g')

# OPTIONAL per-project escape hatch: a TIGHT allowlist of VERIFIED stdlib-only scripts
# (no cv2/torch/easyocr/matplotlib imports, direct OR transitive) may run on the login
# node without sbatch, for fast iteration. Set both regexes in the project's
# .claude/settings.json env block; unset = no exemptions at all.
#   CLAUDE_LOGIN_SAFE_RE   scripts that are verified light
#   CLAUDE_LOGIN_HEAVY_RE  scripts that would SIGABRT the login node
# A command is exempt only if it names a SAFE script and NO heavy one. Re-verify the
# imports before extending either list — a transitive torch import is enough to crash.
_SAFE="${CLAUDE_LOGIN_SAFE_RE:-}"
_HEAVY="${CLAUDE_LOGIN_HEAVY_RE:-^$}"
if [ -n "$_SAFE" ] && echo "$cmd" | grep -qE "$_SAFE" && ! echo "$cmd" | grep -qE "$_HEAVY"; then exit 0; fi

# Command position: start of line, after a shell separator, or the opening quote of an
# inline script (`bash -c "python …"`).
_SEP='(^|[;&|]|&&|\|\||\(|[[:space:]]do[[:space:]]|[[:space:]]then[[:space:]]|-l?c[[:space:]]*["'"'"'])[[:space:]]*'
# Wrappers that run their argument as the command, plus leading VAR=value assignments.
_WRAP='((env|nohup|time|exec|command|builtin|setsid|nice|timeout|stdbuf|xargs|sh|bash|zsh|dash|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+)([[:space:]]+(-[^[:space:]]+|[0-9.]+[smhd]?))*[[:space:]]+)*'
# Python entry points, optionally path-prefixed (.venv/bin/python).
# gpaw/ase/mpiexec/mpirun are here because they LAUNCH Python without the word `python` ever
# reaching command position: `gpaw python x.py` is `python -m gpaw`, and `mpiexec -n 8 gpaw
# python x.py` starts 8 of them. Both used to pass this guard untouched and thread-bomb the
# login node exactly the way it exists to prevent.
_PY='(([^[:space:]]*/)?(python[0-9.]*|ipython|pytest|py\.test|pip[0-9]*|jupyter[-a-z]*|torchrun|accelerate|streamlit|uvicorn|gunicorn|mypy|black|isort|pylint|flake8|tox|uvx|gpaw|ase|mpiexec|mpirun)|uv[[:space:]]+(run|pip|sync|tool)|(poetry|conda|mamba|pipx)[[:space:]]+run)([[:space:]]|$)'
if echo "$scrubbed" | grep -qE "${_SEP}${_WRAP}${_PY}"; then
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Login-node Python is BLOCKED in this form. The binding limit is the per-user THREAD cap (ulimit -u, varies by node — read it live): NumPy/PyTorch/MKL default to one thread PER CORE, so an uncapped import can want ~56 threads and abort() the moment a fork fails. Two ways forward:\n  QUICK CHECK (import test, --help, a few rows, the keys in a checkpoint): run it through bash .claude/bin/loginpy <args> — every thread pool pinned to 1, wall clock capped.\n  GPAW/ASE: there is no venv, so point loginpy at the module interpreter — `module load GPAW/<ver>-<toolchain>` then `LOGINPY_PYTHON=$(command -v python3) bash .claude/bin/loginpy -m gpaw info`. The gpaw CLI is just `python -m gpaw`.\n  REAL WORK (needs a GPU, a dataset, or more than ~2 min): /sbatch-run <command>, or the template in RUNBOOK.md > The submit template; then read the --output log.\nNotes: CPU partitions (xeon*) lack libGL, so a GUI-linked cv2 fails to import there — use a GPU partition for anything importing cv2. Scripts must live under $HOME (NFS); /tmp is node-local and invisible to the job."}}'
fi
exit 0
