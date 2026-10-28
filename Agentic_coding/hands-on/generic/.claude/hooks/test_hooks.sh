#!/usr/bin/env bash
# Probe every guard hook in this directory with real bypass attempts, and exercise the Stop
# hooks in a throwaway git repo. Run it after copying the bundle into a project, and after
# editing any hook — every line must PASS:
#   bash .claude/hooks/test_hooks.sh
# Hooks that aren't present (e.g. the cluster ones in a generic install) are skipped.
set -u
HD=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HD/../.." && pwd)
command -v jq >/dev/null 2>&1 || { echo "jq is required — the guards fail closed without it"; exit 2; }
pass=0; fail=0

ok()   { pass=$((pass+1)); printf 'PASS  %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL  %s\n' "$1"; }

# check <deny|allow> <hook> <tool> <field> <value>
check() {
  local expect="$1" hook="$HD/$2" out verdict
  [ -f "$hook" ] || return 0
  out=$(jq -n --arg t "$3" --arg k "$4" --arg v "$5" --arg cwd "$ROOT" \
          '{tool_name:$t,cwd:$cwd,tool_input:{($k):$v}}' | CLAUDE_PROJECT_DIR="$ROOT" bash "$hook" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"deny"'; then verdict=deny; else verdict=allow; fi
  if [ "$verdict" = "$expect" ]; then ok "$(printf '%-5s %-24s %s' "$expect" "$2" "$5")"
  else bad "$(printf 'want %-5s got %-5s %-24s %s' "$expect" "$verdict" "$2" "$5")"; fi
}
b() { check "$1" "$2" Bash command "$3"; }

echo "## installation"
# Nobody runs chmod after copying files in, so nothing may depend on it. Claude Code executes a
# hook's command string through a shell: invoked directly, a script without its executable bit
# exits 126, which the hook system treats as a NON-blocking error and lets the tool through —
# every guard silently off. Wrapping each command in `bash` makes the bit irrelevant. This test
# is what keeps it that way.
unwrapped=$(python3 - "$ROOT/.claude/settings.json" <<'PYEOF'
import json, sys
j = json.load(open(sys.argv[1]))
bad = [h["command"] for gs in j.get("hooks", {}).values() for g in gs for h in g["hooks"]
       if not h["command"].lstrip().startswith("bash ")]
print(" | ".join(bad))
PYEOF
)
if [ -z "$unwrapped" ]; then ok "every hook runs via bash (executable bits cannot matter)"
else bad "hook(s) not wrapped in bash — a copy without exec bits disarms them: $unwrapped"; fi
command -v jq >/dev/null 2>&1 && ok "jq is on PATH" || bad "jq missing — every guard fails closed"
# Anything in .claude/rules/ without `paths:` frontmatter loads into EVERY session as a real
# rule. A template or a leftover draft parked there is therefore injected as instructions.
phantom=$(find "$ROOT/.claude/rules" -maxdepth 1 \( -name '*.template' -o -name '*.md.bak' -o -name '*.example' \) 2>/dev/null | sed "s|$ROOT/||" | tr '\n' ' ')
if [ -z "$phantom" ]; then ok "no templates or drafts parked in .claude/rules/"
else bad "these load as live rules every session — move them out of .claude/rules/: $phantom"; fi
# permissions.blockReadsOutsideWorkingDirectories looks like free safety and is not: with it on,
# Claude Code statically parses every Bash command to check what it reads, and anything the
# parser cannot analyse — a $VAR, a quoted string, a heredoc, a for-loop — escalates to a
# permission prompt. In practice that is most real commands, and the flood trains people to
# click through. block_outside_root.sh covers the same paths and stays silent unless it denies.
if grep -q 'blockReadsOutsideWorkingDirectories' "$ROOT/.claude/settings.json" 2>/dev/null; then
  bad "blockReadsOutsideWorkingDirectories is set — it turns every unparseable Bash command into a permission prompt; the root hook already covers this"
else ok "no blockReadsOutsideWorkingDirectories (it prompts on every unparseable command)"; fi

echo "## block_destructive_git.sh"
for c in 'git push --force origin main' 'git push -f origin main' 'git push origin main --force' \
         'git push origin +main' 'git push origin :feature' 'git push --force-with-lease origin main' \
         'git -C . push --force' 'git -c push.default=current push --force' 'timeout 60 git push --force' \
         'bash -c "git push --force"' 'cd x && git push -f' 'echo $(git push --force)' \
         'git reset --hard HEAD~1' 'git reset -q --hard' 'git clean -fd' 'git clean -xdf' 'git clean -d -f' \
         'git checkout .' 'git checkout -- src/' 'git checkout -f main' 'git restore .' 'git restore --worktree .' \
         'git restore --staged --worktree f' 'git branch -D foo' 'git branch --delete --force foo' \
         'git commit --amend --no-edit' 'git rebase -i HEAD~3' 'git pull --rebase' 'git stash drop' \
         'git stash clear' 'git push origin --delete feature' 'git filter-branch --all' 'git reflog expire --all'; do
  b deny block_destructive_git.sh "$c"; done
for c in 'git push origin HEAD' 'git push origin HEAD:main' 'git push --set-upstream origin feat' \
         'git reset HEAD file.py' 'git reset --soft HEAD~1' 'git clean -n' 'git checkout main' \
         'git checkout -b feature' 'git restore --staged file.py' 'git branch -d merged' 'git branch -a' \
         'git commit -m "reset the --hard cases"' 'git stash' 'git stash pop' 'git pull' 'git log --oneline' \
         'echo git push --force' 'grep -r "git reset --hard" docs/'; do
  b allow block_destructive_git.sh "$c"; done

echo "## block_rm_rf.sh"
for c in 'rm -rf build' 'rm -fr build' 'rm -r -f build' 'rm --recursive --force build' 'sudo rm -rf /' \
         '/bin/rm -rf x' 'rm -rfv x' 'cd x && rm -rf y' 'echo $(rm -rf x)' 'xargs rm -rf' \
         'bash -c "rm -rf x"' "sh -c 'rm -rf x'" 'rm -rf -- "$D"' 'rm -R -f x' 'find . -name "*.pyc" -delete'; do
  b deny block_rm_rf.sh "$c"; done
for c in 'rm -r build' 'rm -f file.txt' 'rm file.txt' 'rm -i -r build' 'find . -name "*.pyc"' \
         'alarm -rf' 'ls -rf' 'git rm -r --cached dir' 'echo "use rm -r for directories"'; do
  b allow block_rm_rf.sh "$c"; done

echo "## block_login_node.sh"
for c in 'python x.py' 'python3 -m pytest' 'uv run python x.py' '.venv/bin/python x.py' 'pytest' \
         'env python x.py' 'nohup python x.py &' 'time python x.py' 'timeout 60 python x.py' \
         'nice -n 10 python x.py' 'exec python x.py' 'FOO=1 python x.py' 'bash -c "python x.py"' \
         'pip install torch' 'uv pip install torch' 'uv sync' 'jupyter nbconvert --execute nb.ipynb' \
         'torchrun x.py' 'cd src && python x.py' 'ipython'; do
  b deny block_login_node.sh "$c"; done
for c in 'sbatch --wrap="python x.py"' 'srun python x.py' 'uv run python -m py_compile x.py' \
         'grep python foo.txt' 'ruff check .' 'git status' 'cat python_notes.md' 'echo python' \
         'which python' 'ls .venv/bin/' 'sbatch job.sh' 'sbatch --wrap="cd x && python y.py"' \
         '.claude/bin/loginpy x.py' 'loginpy -c "import torch"' 'loginpy -m pytest tests/' \
         'cd src && loginpy x.py' 'echo loginpy'; do
  b allow block_login_node.sh "$c"; done
# The allowed segment is scrubbed, not the whole command: a chained bare python still denies.
for c in 'loginpy a.py; python b.py' 'loginpy a.py && python b.py' 'python x.py && sbatch y.sh' \
         'python a.py; loginpy b.py'; do
  b deny block_login_node.sh "$c"; done

echo "## block_outside_root.sh"
for c in 'ls ..' 'cd .. && ls' 'ls ../' 'cat ../other/secret' 'ls ~' 'ls ~/' 'ls ~root' 'ls ~root/x' \
         'ls ~nosuchuser_zz' 'ls $HOME' 'ls "$HOME"' 'ls ${HOME}/x' 'ls /home/other' 'find / -name x' \
         'ls --directory=/etc/../home' 'cat $OTHER/secret' 'grep -r foo $HOME/projects'; do
  b deny block_outside_root.sh "$c"; done
for c in 'ls .' 'ls -la' 'grep -r foo .' 'cat src/x.py' 'ls /tmp' 'cat $HOME/.cache/run-1.log' \
         'ls $CLAUDE_PROJECT_DIR/src' 'cat /etc/hosts' 'python -c "print(1)" 2>/dev/null' \
         'git log HEAD..main' 'sed "s~a~b~" f' 'ls --color=auto' 'diff a.txt b.txt'; do
  b allow block_outside_root.sh "$c"; done
# A lexical check is only worth having if it survives the obvious ways around it.
for c in 'H=$HOME; ls $H' 'cat "$SECRET"' 'ls "${H}"' 'D=/home/other; ls $D' \
         'ls $(dirname /home/other/x)' 'ls `echo /home/other`' 'cat ~other/notes' 'ls ~/..'; do
  b deny block_outside_root.sh "$c"; done
for c in 'echo $USER' 'for n in 1 2; do sed -n "${n}p" f.txt; done' 'ls $CLAUDE_PROJECT_DIR/src' \
         'cat $HOME/.cache/x.log' 'wc -l "src/a b.py"' 'find . -name "*.py" -exec wc -l {} \;'; do
  b allow block_outside_root.sh "$c"; done
check deny  block_outside_root.sh Read file_path "$HOME/.ssh/config"
check deny  block_outside_root.sh Read file_path "../x"
check deny  block_outside_root.sh Grep path "$HOME"
check deny  block_outside_root.sh Glob path "/"
check allow block_outside_root.sh Read file_path "$ROOT/CLAUDE.md"
check allow block_outside_root.sh Read file_path "src/x.py"
check allow block_outside_root.sh Grep path "$ROOT"

# The Stop hooks need a working git (on a Mac with an unaccepted Xcode license, every git
# call fails and the hooks exit 0 by design) — skip rather than mis-report.
gt=$(mktemp -d); if git -C "$gt" init -q . >/dev/null 2>&1; then git_ok=1; else git_ok=0; fi; rm -rf "$gt"
[ "$git_ok" = 1 ] || echo "SKIP  Stop-hook tests: git is not usable here ($(git --version 2>&1 | head -1))"

echo "## setup gate"
sg="$HD/block_until_setup.sh"
marker="$ROOT/.claude/setup/SETUP_REQUIRED"
if [ -f "$sg" ]; then
  gate() { jq -n --arg f "$1" --arg p "$ROOT" '{tool_name:"Edit",cwd:$p,tool_input:{file_path:$f}}' \
             | CLAUDE_PROJECT_DIR="$ROOT" bash "$sg" 2>/dev/null | grep -q '"deny"' && echo deny || echo allow; }
  want() { if [ "$(gate "$2")" = "$3" ]; then ok "$1"; else bad "$1 (wanted $3)"; fi; }
  gb() { jq -n --arg c "$1" --arg p "$ROOT" '{tool_name:"Bash",cwd:$p,tool_input:{command:$c}}' \
           | CLAUDE_PROJECT_DIR="$ROOT" bash "$sg" 2>/dev/null | grep -q '"deny"' && echo deny || echo allow; }
  wantb() { if [ "$(gb "$2")" = "$3" ]; then ok "$1"; else bad "$1 (wanted $3)"; fi; }
  if [ -f "$ROOT/.claude/setup/SETUP_IN_PROGRESS" ]; then
    # /setup is running: it must be able to run the project's own commands to verify them.
    wantb "in progress: the project's test command runs" "pytest -q" allow
    want  "in progress: source files are still gated"    "$ROOT/src/main.py" deny
  elif [ -f "$marker" ]; then
    # Setup pending: source is gated, the files setup must write are not.
    want "pending: a source file is denied"        "$ROOT/src/main.py"             deny
    want "pending: a test file is denied"          "tests/test_x.py"               deny
    want "pending: CLAUDE.md is writable"          "$ROOT/CLAUDE.md"               allow
    want "pending: .claude/rules is writable"      "$ROOT/.claude/rules/project.md" allow
    want "pending: a nested CLAUDE.md is writable" "$ROOT/src/CLAUDE.md"           allow
    want "pending: scratch/ is writable"           "$ROOT/scratch/probe.py"        allow
    wantb "pending: ls is allowed"                 "ls -la"                        allow
    wantb "pending: read-only git is allowed"      "git status"                    allow
    wantb "pending: the hook tests are allowed"    "bash .claude/hooks/test_hooks.sh" allow
    wantb "pending: a test run is denied"          "pytest"                        deny
    wantb "pending: a build is denied"             "make"                          deny
    wantb "pending: git commit is denied"          "git commit -m x"               deny
    wantb "pending: a redirection is denied"       "echo hi > f.py"                deny
    wantb "pending: appending to a file is denied" "ls >> log.txt"                 deny
    wantb "pending: stderr discard is allowed"     "cat f 2>/dev/null"             allow
    wantb "pending: 2>&1 is allowed"               "ls -la x 2>&1"                 allow
    wantb "pending: stdout discard is allowed"     "grep -q foo f >/dev/null"      allow
    wantb "pending: a chained cat/echo/ls is allowed" "cat a 2>/dev/null; echo ---; ls -la b" allow
    wantb "pending: a chained denial still denies" "ls && pytest"                  deny
  else
    # Released: the hook must be inert, not merely quiet about some paths.
    want  "released: source files are not gated" "$ROOT/src/main.py" allow
    wantb "released: shell commands are not gated" "pytest" allow
  fi
fi

echo "## loginpy"
lp="$ROOT/.claude/bin/loginpy"
if [ -f "$lp" ]; then
  [ -x "$lp" ] && ok "loginpy is executable" || bad "loginpy is not executable"
  out=$(LOGINPY_PYTHON=python3 CLAUDE_PROJECT_DIR=/nonexistent "$lp" \
          -c 'import os;print(os.environ["OMP_NUM_THREADS"],os.environ["MKL_NUM_THREADS"],os.environ["OPENBLAS_NUM_THREADS"])' 2>&1)
  [ "$out" = "1 1 1" ] && ok "loginpy pins the thread pools to 1" || bad "loginpy thread pins: $out"
  LOGINPY_PYTHON=python3 LOGINPY_TIMEOUT=2 CLAUDE_PROJECT_DIR=/nonexistent "$lp" \
    -c 'import time;time.sleep(30)' >/dev/null 2>&1
  [ $? -eq 124 ] && ok "loginpy enforces LOGINPY_TIMEOUT" || bad "loginpy did not time out"
  "$lp" >/dev/null 2>&1; [ $? -eq 2 ] && ok "loginpy with no args prints usage" || bad "loginpy no-args exit"
fi

echo "## doc_check.sh"
dc="$HD/doc_check.sh"
if [ -f "$dc" ]; then
  dctmp=$(mktemp -d)
  stamps="$dctmp/claude_harness_doccheck $dctmp/claude_niflheim_doccheck"
  XDG_CACHE_HOME="$dctmp/absent" CLAUDE_PROJECT_DIR="$ROOT" bash "$dc" 2>/dev/null | grep -q 'harness-docs' \
    && ok "doc_check nudges when never checked" || bad "doc_check silent with no stamp"
  for s in $stamps; do date +%Y-%m-%d > "$s"; done
  [ -z "$(XDG_CACHE_HOME="$dctmp" CLAUDE_PROJECT_DIR="$ROOT" bash "$dc" 2>/dev/null)" ] \
    && ok "doc_check is silent when the stamps are fresh" || bad "doc_check nudged on a fresh stamp"
  touch -t 202001010000 $stamps
  XDG_CACHE_HOME="$dctmp" CLAUDE_PROJECT_DIR="$ROOT" bash "$dc" 2>/dev/null | grep -q 'harness-docs' \
    && ok "doc_check nudges on a stale stamp" || bad "doc_check silent on a stale stamp"
  if [ -f "$ROOT/.claude/skills/niflheim-docs/SKILL.md" ]; then
    XDG_CACHE_HOME="$dctmp" CLAUDE_PROJECT_DIR="$ROOT" bash "$dc" 2>/dev/null | grep -q 'niflheim-docs' \
      && ok "doc_check also nudges for the cluster docs where that skill exists" || bad "doc_check missed the cluster-docs check"
  else
    XDG_CACHE_HOME="$dctmp" CLAUDE_PROJECT_DIR="$ROOT" bash "$dc" 2>/dev/null | grep -q 'niflheim-docs' \
      && bad "doc_check nudges for cluster docs without the skill" || ok "doc_check skips the cluster-docs check where the skill is absent"
  fi
  [ -z "$(CLAUDE_DOCCHECK_DAYS=0 XDG_CACHE_HOME="$dctmp" CLAUDE_PROJECT_DIR="$ROOT" bash "$dc" 2>/dev/null)" ] \
    && ok "CLAUDE_DOCCHECK_DAYS=0 disables both checks" || bad "doc_check ignored DAYS=0"
  rm -rf "$dctmp"
fi

echo "## stop_untracked_gate.sh"
gate="$HD/stop_untracked_gate.sh"
if [ -f "$gate" ] && [ "$git_ok" = 1 ]; then
  tmp=$(mktemp -d); cachedir=$(mktemp -d); export XDG_CACHE_HOME="$cachedir"   # stamp cache must live OUTSIDE the repo
  git -C "$tmp" init -q . && git -C "$tmp" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  run_gate() { printf '{"stop_hook_active":%s}' "$1" | CLAUDE_PROJECT_DIR="$tmp" bash "$gate" >/dev/null 2>&1; echo $?; }
  expect_exit() { if [ "$2" = "$3" ]; then ok "exit $3  $1"; else bad "want exit $3 got $2  $1"; fi; }
  expect_exit "clean tree passes"                          "$(run_gate false)" 0
  touch "$tmp/stray.txt"
  expect_exit "new stray blocks the stop"                  "$(run_gate false)" 2
  expect_exit "same stray is not re-raised"                "$(run_gate false)" 0
  touch "$tmp/stray2.txt"
  expect_exit "another stray blocks again"                 "$(run_gate false)" 2
  touch "$tmp/stray3.txt"
  expect_exit "Claude already answered this turn → passes" "$(run_gate true)" 0
  printf 'scratch/\n' > "$tmp/.gitignore"; git -C "$tmp" add .gitignore
  mkdir -p "$tmp/scratch"; touch "$tmp/scratch/tmp.py"; rm "$tmp"/stray*.txt
  expect_exit "scratch/ is ignored, tree clean"            "$(run_gate false)" 0
  msg=$(touch "$tmp/s.txt"; printf '{}' | CLAUDE_PROJECT_DIR="$tmp" bash "$gate" 2>&1 >/dev/null)
  if printf '%s' "$msg" | grep -q 's.txt'; then ok "stray list reaches Claude on stderr"; else bad "stderr lacked the stray list"; fi
  rm -rf "$tmp" "$cachedir"; unset XDG_CACHE_HOME
fi

echo "## stop_autocommit.sh"
ac="$HD/stop_autocommit.sh"
if [ -f "$ac" ] && [ "$git_ok" = 1 ]; then
  tmp=$(mktemp -d); bare=$(mktemp -d)
  git -C "$tmp" init -q . && git -C "$tmp" config user.email t@t && git -C "$tmp" config user.name t
  echo a > "$tmp/f.txt" && git -C "$tmp" add f.txt && git -C "$tmp" commit -q -m add
  echo b > "$tmp/f.txt"; touch "$tmp/new.txt"; before=$(git -C "$tmp" rev-parse HEAD)
  out=$(printf '{}' | CLAUDE_PROJECT_DIR="$tmp" CLAUDE_AUTO_PUSH=0 bash "$ac" 2>&1)
  if [ "$(git -C "$tmp" rev-parse HEAD)" != "$before" ] && git -C "$tmp" ls-files --others --exclude-standard | grep -q new.txt \
     && printf '%s' "$out" | grep -q 'CLAUDE_AUTO_PUSH'; then ok "commits tracked change only; no push without CLAUDE_AUTO_PUSH"
  else bad "autocommit without push: $out"; fi
  git init -q --bare "$bare" && git -C "$tmp" remote add origin "$bare"
  echo c > "$tmp/f.txt"; branch=$(git -C "$tmp" symbolic-ref --short HEAD)
  out=$(printf '{}' | CLAUDE_PROJECT_DIR="$tmp" CLAUDE_AUTO_PUSH=1 bash "$ac" 2>&1)
  if [ "$(git -C "$bare" rev-parse --verify "refs/heads/$branch" 2>/dev/null)" = "$(git -C "$tmp" rev-parse HEAD)" ]; then ok "pushes when CLAUDE_AUTO_PUSH=1"
  else bad "push with CLAUDE_AUTO_PUSH=1: $out"; fi
  rm -rf "$tmp" "$bare"
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
