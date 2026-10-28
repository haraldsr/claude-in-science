#!/usr/bin/env bash
# PreToolUse hook: CONFINE the agent to the project ROOT.
#
# Why: everything outside the project root belongs to something else — other repositories,
# other people's data on a shared filesystem, your own dotfiles and credentials. A stray
# `grep -r ~`, a `cat ../other_project/...`, or an edit one directory up is a privacy problem
# before it is anything else, and on a network filesystem an expensive one. This hook denies
# any tool call that reaches outside ROOT, except for an explicit allowlist. Pair it with
# `permissions.blockReadsOutsideWorkingDirectories` (built in, file tools, every mode).
#
# ROOT      = $CLAUDE_PROJECT_DIR (fallback: the tool call's cwd).
# ALLOWED   = ROOT, $HOME/.cache (job logs, tool caches), $TMPDIR / /tmp,
#             read-only system prefixes (/usr /bin /sbin /lib* /opt /etc /proc /sys),
#             plus anything in $CLAUDE_ROOT_ALLOW (colon-separated).
#
# Covers file tools (Read/Edit/Write/NotebookEdit/Glob/Grep) by their path argument, and
# Bash by scanning the command for absolute, ~, ~user, $HOME, $VAR/… and ..-escaping path
# tokens. Known limit: a variable holding a path (`H=$HOME; ls $H`) and a script that does
# the walking (`bash walk.sh`) are opaque to a lexical check.
# Fail-closed: if jq is missing, deny. Probe it with test_hooks.sh and /root-lock.
set -u

if ! command -v jq >/dev/null 2>&1; then
  printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"jq missing from PATH — the root-confinement guard cannot parse the call, blocking for safety (fail-closed)."}}'
  exit 0
fi

payload=$(cat)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // ""')
cwd=$(printf '%s' "$payload" | jq -r '.cwd // ""')
ROOT="${CLAUDE_PROJECT_DIR:-$cwd}"
[ -n "$ROOT" ] || exit 0
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || exit 0
[ -n "$cwd" ] || cwd="$ROOT"

deny() {
  jq -n --arg p "$1" --arg root "$ROOT" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("Path outside ROOT blocked: " + $p + "\n\nROOT is " + $root + ". This project is confined to it: everything outside belongs to something else — other repositories, data belonging to other people on a shared filesystem, your own dotfiles and credentials.\n\nAllowed outside ROOT: $HOME/.cache (job logs), $TMPDIR, and read-only system paths. A path built from an unknown variable is denied too — write the literal path inside ROOT instead. If you genuinely need another location, ask the user; do not work around this hook.")}}'
  exit 0
}

# Lexical .. / . collapse, no filesystem access needed.
collapse() {
  printf '%s' "$1" | awk -F/ '{
    n=0
    for (i=1;i<=NF;i++){
      if ($i=="" || $i==".") continue
      if ($i==".."){ if(n>0) n--; continue }
      s[++n]=$i
    }
    out=""
    for (i=1;i<=n;i++) out=out "/" s[i]
    print (out=="" ? "/" : out)
  }'
}

# Resolve a path token (possibly non-existent) to an absolute, normalised form.
norm() {
  local p="$1" user rest home
  case "$p" in
    "~") p="$HOME" ;;
    "~/"*) p="$HOME/${p#\~/}" ;;
    "~"*)                                   # ~user or ~user/path
      user="${p#\~}"; user="${user%%/*}"; rest="${p#\~"$user"}"
      case "$user" in ""|*[!A-Za-z0-9._-]*) printf '%s' "/~/unparseable"; return ;; esac
      home=$(eval "printf '%s' ~$user" 2>/dev/null)
      case "$home" in /*) p="$home$rest" ;; *) printf '%s' "/~/$user"; return ;; esac ;;
    '$HOME'|'${HOME}') p="$HOME" ;;
    '$HOME/'*) p="$HOME/${p#\$HOME/}" ;;
    '${HOME}/'*) p="$HOME/${p#\$\{HOME\}/}" ;;
    '$CLAUDE_PROJECT_DIR'|'${CLAUDE_PROJECT_DIR}') p="$ROOT" ;;
    '$CLAUDE_PROJECT_DIR/'*) p="$ROOT/${p#\$CLAUDE_PROJECT_DIR/}" ;;
    '${CLAUDE_PROJECT_DIR}/'*) p="$ROOT/${p#\$\{CLAUDE_PROJECT_DIR\}/}" ;;
    '$PWD'|'${PWD}') p="$cwd" ;;
    '$PWD/'*) p="$cwd/${p#\$PWD/}" ;;
    '${PWD}/'*) p="$cwd/${p#\$\{PWD\}/}" ;;
    '$TMPDIR'|'${TMPDIR}') p="${TMPDIR:-/tmp}" ;;
    '$TMPDIR/'*) p="${TMPDIR:-/tmp}/${p#\$TMPDIR/}" ;;
    '${TMPDIR}/'*) p="${TMPDIR:-/tmp}/${p#\$\{TMPDIR\}/}" ;;
    '$'*) printf '%s' "/\$/unresolved"; return ;;   # unknown variable used as a path
    /*) ;;
    *) p="$cwd/$p" ;;
  esac
  collapse "$p"
}

is_allowed() {
  local p="$1" a
  case "$p" in
    "$ROOT"|"$ROOT"/*) return 0 ;;
    "$HOME"/.cache|"$HOME"/.cache/*) return 0 ;;
    /tmp|/tmp/*|/var/tmp/*) return 0 ;;
    /usr/*|/bin/*|/sbin/*|/lib*|/opt/*|/etc/*|/proc/*|/sys/*|/dev/null|/dev/stdin|/dev/stdout|/dev/stderr) return 0 ;;
  esac
  [ -n "${TMPDIR:-}" ] && case "$p" in "${TMPDIR%/}"|"${TMPDIR%/}"/*) return 0 ;; esac
  IFS=':' read -r -a _extra <<< "${CLAUDE_ROOT_ALLOW:-}"
  for a in "${_extra[@]:-}"; do
    [ -z "$a" ] && continue
    case "$p" in "${a%/}"|"${a%/}"/*) return 0 ;; esac
  done
  return 1
}

# Commands whose arguments are paths. For these, an argument we cannot resolve is not
# something to wave through: `H=$HOME; ls $H` is the obvious way around a lexical check, and
# the whole point is that it should not work.
takes_paths() {
  case "$1" in
    ls|cat|head|tail|less|more|cd|cp|mv|rm|mkdir|rmdir|touch|ln|stat|du|df|file|wc|chmod|chown\
    |find|grep|egrep|fgrep|rg|sed|awk|diff|cmp|tar|zip|unzip|rsync|scp|realpath|readlink|dirname\
    |basename|tree|source|.|truncate|install|shred|split|sort|uniq|cut|tee|xxd|od|strings) return 0 ;;
  esac
  return 1
}

case "$tool" in
  Bash)
    cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')

    # Pass 1: a path-taking command must not be handed an argument we cannot resolve.
    _oifs=$IFS; IFS='
'
    for seg in $(printf '%s\n' "$cmd" | tr ';&|()`' '\n'); do
      IFS=$_oifs
      # shellcheck disable=SC2086
      set -- $seg
      while [ $# -gt 0 ]; do
        case "$1" in
          *=*) shift ;;                                   # VAR=value prefix
          sudo|env|command|builtin|exec|nohup|time|timeout|nice|stdbuf|xargs) shift ;;
          *) break ;;
        esac
      done
      [ $# -eq 0 ] && { IFS='
'; continue; }
      w="${1##*/}"; shift
      if takes_paths "$w"; then
        for a in "$@"; do
          a="${a//\"/}"; a="${a//\'/}"      # quotes are not part of the path
          case "$a" in
            -*) continue ;;
            '$'[A-Za-z_]*|'${'[A-Za-z_]*|*'$('*|*'`'*)
              case "$a" in
                '$HOME'*|'${HOME}'*|'$PWD'*|'${PWD}'*|'$TMPDIR'*|'${TMPDIR}'*) continue ;;
                '$CLAUDE_PROJECT_DIR'*|'${CLAUDE_PROJECT_DIR}'*) continue ;;
              esac
              deny "$a" ;;
          esac
        done
      fi
      IFS='
'
    done
    IFS=$_oifs
    # Candidate path tokens; quotes and shell punctuation become separators.
    for tok in $(printf '%s\n' "$cmd" | tr '"'"'"'`(),;|&<>' ' ' | tr ' ' '\n'); do
      case "$tok" in -*=*) tok="${tok#*=}" ;; esac       # --flag=/path → the path part
      case "$tok" in
        ""|-*) continue ;;
        ..|../*|*/..|*/../*) ;;                                      # parent references
        /*|'~'*|'$HOME'|'$HOME/'*|'${HOME}'|'${HOME}/'*) ;;          # absolute / home-rooted
        '$'[A-Za-z_]*/*|'${'[A-Za-z_]*'}'/*) ;;                      # $VAR/… (resolved or denied)
        *) continue ;;
      esac
      p=$(norm "$tok")
      is_allowed "$p" || deny "$tok"
    done
    ;;
  Read|Edit|Write|NotebookEdit|Glob|Grep)
    for key in file_path notebook_path path; do
      v=$(printf '%s' "$payload" | jq -r --arg k "$key" '.tool_input[$k] // empty')
      [ -z "$v" ] && continue
      p=$(norm "$v")
      is_allowed "$p" || deny "$v"
    done
    ;;
esac
exit 0
