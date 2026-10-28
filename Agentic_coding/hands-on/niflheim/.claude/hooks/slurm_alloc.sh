#!/usr/bin/env bash
# SessionStart hook: inject the GPU run model + live partition state, and point at the
# single copy of the submit template (RUNBOOK.md). Re-runs after /compact.
#
# Verified on the cluster: interactive `srun` step-launch to GPU compute nodes does NOT work
# from any login node — the login node can't resolve compute-node names (s004 …), so srun
# fails with "_fwd_tree_get_addr: can't find address for host sNNN, check slurm.conf". Same
# on svol/thul (site slurm.conf/DNS limitation). There is NO persistent reusable allocation:
# every run goes through `sbatch`, whose script runs ON the compute node.
set -u
command -v jq >/dev/null 2>&1 || exit 0

avail=$(sinfo -h -p sm3090el8 -o '%P=%t(%D)' 2>/dev/null | tr '\n' ' ')

ctx="Niflheim run model: every run goes through sbatch — interactive srun/salloc step-launch to GPU nodes fails from all login nodes (can't resolve compute-node names), and login-node Python is denied by hook. Use /sbatch-run <command>, or the template in RUNBOOK.md › The submit template (cd to the project, export SSL_CERT_FILE via certifi, run under 'uv run python', log to \$HOME/.cache/run-%j.log). Many items → ONE job (models reload per process). For a quick debug run use sm3090el8 with a small --time (sm3090_devel no longer exists; showpartitions is authoritative). Submit, then watch in the background (one watcher per job) and act on the result. Current GPU partition state: ${avail:-unknown}."

jq -n --arg ctx "$ctx" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
