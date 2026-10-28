#!/usr/bin/env bash
# PreToolUse hook: deny git commands that discard work or rewrite history. Per CLAUDE.md
# (Hard constraints › Safety) these need an explicit ask from the user.
#
# Every git invocation in the command is checked — segments are split on ; && || | &
# newlines, subshells and $(...); wrappers (sudo, env, timeout 60, bash -c, …) and git's
# global options (-C <dir>, -c k=v, --git-dir …) are skipped; then the SUBCOMMAND's flags
# are matched wherever they appear in the segment:
#   reset      --hard, --merge
#   clean      -f / --force in any position or bundle (-fd, -xdf, -d -f)
#   push       --force*, -f (incl. bundles), +refspec, :refspec, -d/--delete, --mirror
#   checkout   ".", "--", -f/--force            (pathspec / forced discard)
#   restore    anything but a pure --staged     (worktree discard)
#   branch     -D, or -d/--delete together with -f/--force
#   commit     --amend
#   rebase, pull --rebase/-r, stash drop|clear, filter-branch, filter-repo,
#   reflog expire|delete, update-ref -d
# Fail CLOSED: if jq is missing, deny. Probe it with test_hooks.sh.
set -u
if ! command -v jq >/dev/null 2>&1; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"jq missing from PATH — destructive-git guard cannot parse the command, blocking for safety (fail-closed)."}}'
  exit 0
fi
cmd=$(jq -r '.tool_input.command // ""')
[ -n "$cmd" ] || exit 0

deny() {
  jq -n --arg cmd "$cmd" --arg why "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("Destructive git blocked (" + $why + "): " + $cmd + "\n\nThis discards work or rewrites history. Per CLAUDE.md it needs an explicit ask — stop and ask the user before running it. If this is a false positive (the flag was inside a commit message, say), rephrase.")}}'
  exit 0
}

# Does any token after the subcommand match the glob pattern $1?
has() { local x; for x in ${rest[@]+"${rest[@]}"}; do case "$x" in $1) return 0 ;; esac; done; return 1; }

# One segment per line: quotes dropped, shell separators / subshells / substitutions split.
segs=$(printf '%s\n' "$cmd" | tr -d '"'"'"'' | tr '`;&|()' '\n\n\n\n\n\n')

while IFS= read -r seg; do
  t=(); read -r -a t <<< "$seg"
  n=${#t[@]}; i=0
  # Skip wrappers, shell keywords, env assignments and their flag/numeric args.
  while [ "$i" -lt "$n" ]; do
    case "${t[$i]}" in
      sudo|env|command|builtin|exec|nohup|time|timeout|nice|stdbuf|xargs|sh|bash|zsh|dash|ksh|do|then|else|\{|\}|\!|*=*|-*|[0-9]*) i=$((i+1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || continue
  case "${t[$i]}" in git|*/git) ;; *) continue ;; esac
  i=$((i+1))
  while [ "$i" -lt "$n" ]; do          # git's own global options
    case "${t[$i]}" in
      -C|-c|--git-dir|--work-tree|--namespace|--exec-path) i=$((i+2)) ;;
      -*) i=$((i+1)) ;;
      *) break ;;
    esac
  done
  [ "$i" -lt "$n" ] || continue
  sub="${t[$i]}"
  rest=("${t[@]:$((i+1))}")
  case "$sub" in
    reset)    { has '--hard' || has '--merge'; } && deny "reset --hard/--merge" ;;
    clean)    { has '--force' || has '-f*' || has '-[!-]*f*'; } && deny "clean -f" ;;
    push)     { has '--force*' || has '-f*' || has '-[!-]*f*' || has '+*' || has ':*' || has '-d' || has '--delete' || has '--mirror'; } && deny "force-push / delete" ;;
    checkout) { has '.' || has '--' || has '--force' || has '-f*' || has '-[!-]*f*'; } && deny "checkout discards changes" ;;
    restore)  { { has '--staged' || has '-S'; } && ! { has '--worktree' || has '-W'; }; } || deny "restore discards worktree changes" ;;
    branch)   { has '-D*' || has '-[!-]*D*' || { { has '-d' || has '--delete'; } && { has '-f' || has '--force'; }; }; } && deny "branch -D" ;;
    commit)   has '--amend' && deny "commit --amend rewrites history" ;;
    rebase)   deny "rebase rewrites history" ;;
    pull)     { has '--rebase*' || has '-r'; } && deny "pull --rebase rewrites history" ;;
    stash)    { has 'drop' || has 'clear'; } && deny "stash drop/clear" ;;
    filter-branch|filter-repo) deny "history rewrite" ;;
    reflog)   { has 'expire' || has 'delete'; } && deny "reflog expire/delete" ;;
    update-ref) has '-d' && deny "update-ref -d" ;;
  esac
done <<< "$segs"
exit 0
