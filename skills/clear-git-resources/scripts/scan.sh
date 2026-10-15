#!/usr/bin/env bash
# scan.sh - the read-only half of /clear-git-resources.
#
# Lists the git resources of ONE project that look stale, grouped by how safe it is to delete them, and the
# exact command that would delete each one. It deletes nothing itself: the skill shows this list to the
# person and runs only the commands they said yes to.
#
# usage: bash scan.sh [--project <dir>] [--wt-root <dir>] [--fetch] [--days <n>] [--limit <n>]
#   --project  any folder inside the project (main checkout or a worktree); default: the current folder
#   --wt-root  the worktree root the project's CLAUDE.md names; default: C:\wt on Windows, ~/wt elsewhere
#   --fetch    run `git fetch --prune origin` first, so remote branches deleted elsewhere drop out
#   --days     a folder or file in the worktree root is offered only when older than this (default 2)
#   --limit    the branch limit the session-start hook uses (default 20); only echoed in the COUNT line
#
# Output, one record per line, tab-separated:
#   SCAN    project=<main checkout> default=<branch> remote=<name|none> wt_root=<dir> fetched=yes|no pruned=<n> gh=yes|no
#   COUNT   local=<n> remote=<n> total=<n> limit=<n> over=yes|no        (the same count the hook uses)
#   GROUP   <id>  <n>  offer=yes|ask|no  <title>                      (only groups that have items)
#   ITEM    <id>  <name>  <why it is here>  <command that deletes it>  (command empty for offer=no)
#   NOTE    <something the person should know>
#   SUMMARY offer=<n> ask=<n> keep=<n>
# offer=yes: safe to delete (the work is on the default branch, or the thing is already gone).
# offer=ask: deleting loses something; it needs the person's word.
# offer=no:  never offered (the default branch, audit branches, open pull requests, anything in flight,
#            other repositories' checkouts, anything changed in the last --days days).
#
# Portable bash: runs under Git Bash, macOS bash and Linux. No GNU-only flags.

set -uo pipefail

PROJECT_ARG="." WT_ROOT="" FETCH=0 DAYS=2 LIMIT=20
while [ $# -gt 0 ]; do
    case "$1" in
        --project) PROJECT_ARG="$2"; shift 2 ;;
        --wt-root) WT_ROOT="$2"; shift 2 ;;
        --fetch) FETCH=1; shift ;;
        --days) DAYS="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        -h|--help) sed -n '2,27p' "$0"; exit 0 ;;
        *) printf 'scan.sh: unknown option %s\n' "$1" >&2; exit 2 ;;
    esac
done

command -v git >/dev/null 2>&1 || { printf 'NOTE\tgit is not on the path; nothing can be scanned\n'; exit 1; }

# --- where we are ---------------------------------------------------------------------------------------
MAIN=$(cd "$PROJECT_ARG" 2>/dev/null && cd "$(git rev-parse --git-common-dir 2>/dev/null)/.." 2>/dev/null && pwd -P)
[ -n "$MAIN" ] && [ -d "$MAIN/.git" ] || { printf 'NOTE\t%s is not inside a git repository\n' "$PROJECT_ARG"; exit 1; }
g() { git -C "$MAIN" "$@"; }

if [ -z "$WT_ROOT" ]; then
    case "$(uname -s 2>/dev/null)" in MINGW*|MSYS*|CYGWIN*) WT_ROOT="/c/wt" ;; *) WT_ROOT="$HOME/wt" ;; esac
fi

REMOTE=origin
g remote get-url "$REMOTE" >/dev/null 2>&1 || REMOTE=""

DEFAULT=""
[ -n "$REMOTE" ] && DEFAULT=$(g symbolic-ref -q --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s#^$REMOTE/##")
if [ -z "$DEFAULT" ]; then
    for c in main master; do
        if { [ -n "$REMOTE" ] && g show-ref --verify -q "refs/remotes/$REMOTE/$c" 2>/dev/null; } || g show-ref --verify -q "refs/heads/$c" 2>/dev/null; then DEFAULT=$c; break; fi
    done
fi
[ -n "$DEFAULT" ] || DEFAULT=$(g rev-parse --abbrev-ref HEAD 2>/dev/null)
BASE="refs/heads/$DEFAULT"
[ -n "$REMOTE" ] && g show-ref --verify -q "refs/remotes/$REMOTE/$DEFAULT" 2>/dev/null && BASE="refs/remotes/$REMOTE/$DEFAULT"

PRUNED=0 FETCHED=no
if [ "$FETCH" = "1" ] && [ -n "$REMOTE" ]; then
    PRUNED=$(g fetch --prune "$REMOTE" 2>&1 | grep -c '\[deleted\]' || true)
    FETCHED=yes
fi

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t clear-git); trap 'rm -rf "$TMP"' EXIT

# --- pull requests, one call ----------------------------------------------------------------------------
GH=no
if [ -n "$REMOTE" ] && command -v gh >/dev/null 2>&1; then
    if (cd "$MAIN" && gh pr list --state all --limit 500 --json headRefName,state,number \
            --jq '.[] | "\(.headRefName)\t\(.state)\t\(.number)"' > "$TMP/prs" 2>/dev/null); then
        GH=yes
    fi
fi
pr_state() {  # branch -> "OPEN <n>" | "MERGED <n>" | "CLOSED <n>" | ""   (open wins, then merged)
    [ "$GH" = "yes" ] || return 0
    local rows; rows=$(awk -F'\t' -v b="$1" '$1==b {print $2, $3}' "$TMP/prs")
    [ -n "$rows" ] || return 0
    printf '%s\n' "$rows" | grep -m1 '^OPEN'   && return 0
    printf '%s\n' "$rows" | grep -m1 '^MERGED' && return 0
    printf '%s\n' "$rows" | head -n1
}

# --- what is never offered ------------------------------------------------------------------------------
INFLIGHT=""
if [ -f "$WT_ROOT/in-flight.json" ]; then
    INFLIGHT=$(grep -oE '"issue"[[:space:]]*:[[:space:]]*[0-9]+' "$WT_ROOT/in-flight.json" 2>/dev/null | grep -oE '[0-9]+$' | sort -u | tr '\n' ' ')
fi
in_flight() {  # branch or folder name -> 0 when it belongs to an issue in flight (feat/<N>-..., <N>-...)
    local n; n=$(printf '%s' "$1" | sed -n 's#^\(feat/\)\{0,1\}\([0-9][0-9]*\)-.*#\2#p')
    [ -n "$n" ] && case " $INFLIGHT " in *" $n "*) return 0 ;; esac
    return 1
}
HEAD_BRANCH=$(g rev-parse --abbrev-ref HEAD 2>/dev/null)
protected_branch() {  # branch -> 0 when never offered
    case "$1" in "$DEFAULT"|audit/*|HEAD) return 0 ;; esac
    [ "$1" = "$HEAD_BRANCH" ] && return 0
    in_flight "$1"
}
merged() { g merge-base --is-ancestor "$1" "$BASE" 2>/dev/null; }
ahead()  { g rev-list --count "$BASE..$1" 2>/dev/null || echo '?'; }
when()   { g log -1 --format=%cs "$1" 2>/dev/null; }
norm()   { (cd "$1" 2>/dev/null && pwd -P); }

item() {  # group name why cmd
    printf 'ITEM\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$TMP/g.$1"
}

# --- worktrees ------------------------------------------------------------------------------------------
: > "$TMP/wt-branches"; : > "$TMP/wt-paths"
wt_path="" wt_branch="" wt_detached=0 wt_locked=0 wt_prunable=0
flush_wt() {
    [ -n "$wt_path" ] || return 0
    local n="$wt_path" why="" dirty=0 a st rm_cmd br_cmd
    if [ "$(norm "$wt_path")" = "$(norm "$MAIN")" ]; then
        :  # the main checkout itself
    elif [ "$wt_prunable" = "1" ]; then
        item wt-prunable "$n" "registered as a worktree but its folder is gone" "git -C \"$MAIN\" worktree prune"
    else
        norm "$wt_path" >> "$TMP/wt-paths"
        [ -n "$wt_branch" ] && printf '%s\n' "$wt_branch" >> "$TMP/wt-branches"
        [ -d "$wt_path" ] && [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null | head -n1)" ] && dirty=1
        rm_cmd="git -C \"$MAIN\" worktree remove \"$wt_path\" && git -C \"$MAIN\" worktree prune"
        br_cmd=""; [ -n "$wt_branch" ] && br_cmd=" && git -C \"$MAIN\" branch -D \"$wt_branch\""
        [ "$wt_locked" = "1" ] && rm_cmd="git -C \"$MAIN\" worktree unlock \"$wt_path\" && $rm_cmd"
        if [ -n "$wt_branch" ] && in_flight "$wt_branch"; then
            item wt-protected "$n" "branch $wt_branch belongs to an issue in flight (in-flight.json)" ""
        elif [ "$wt_detached" = "1" ]; then
            if [ "$dirty" = "1" ]; then item wt-dirty "$n" "on no branch, has uncommitted changes" "${rm_cmd/worktree remove/worktree remove --force}"
            else item wt-detached "$n" "on no branch (a temporary checkout), clean" "$rm_cmd"; fi
        else
            st=$(pr_state "$wt_branch")
            if [ "$dirty" = "1" ]; then
                why="branch $wt_branch, has uncommitted changes"; [ "$wt_locked" = "1" ] && why="$why, locked"
                item wt-dirty "$n" "$why" "${rm_cmd/worktree remove/worktree remove --force}$br_cmd"
            elif merged "$wt_branch" || [ "${st%% *}" = "MERGED" ]; then
                why="branch $wt_branch is already on $DEFAULT"; [ -n "$st" ] && why="$why (pull request #${st##* } ${st%% *})"
                [ "$wt_locked" = "1" ] && why="$why, locked"
                item wt-done "$n" "$why" "$rm_cmd$br_cmd"
            elif [ "${st%% *}" = "OPEN" ]; then
                item wt-open-pr "$n" "branch $wt_branch has an open pull request #${st##* }" ""
            else
                a=$(ahead "$wt_branch"); why="branch $wt_branch has $a commit(s) not on $DEFAULT, last change $(when "$wt_branch")"
                [ "${st%% *}" = "CLOSED" ] && why="$why, pull request #${st##* } closed without merge"
                [ "$wt_locked" = "1" ] && why="$why, locked"
                item wt-active "$n" "$why" "$rm_cmd$br_cmd"
            fi
        fi
    fi
    wt_path="" wt_branch="" wt_detached=0 wt_locked=0 wt_prunable=0
}
g worktree list --porcelain 2>/dev/null > "$TMP/worktrees"
while IFS= read -r line; do
    case "$line" in
        "worktree "*) flush_wt; wt_path="${line#worktree }" ;;
        "branch refs/heads/"*) wt_branch="${line#branch refs/heads/}" ;;
        detached) wt_detached=1 ;;
        locked*) wt_locked=1 ;;
        prunable*) wt_prunable=1 ;;
    esac
done < "$TMP/worktrees"
flush_wt

checked_out() { grep -qxF "$1" "$TMP/wt-branches" 2>/dev/null; }

# --- local branches -------------------------------------------------------------------------------------
LOCAL_N=0
# Fields are split on \001, not tab: tab is IFS whitespace, so an empty field (no upstream) would collapse.
g for-each-ref refs/heads --format='%(refname:short)%01%(upstream:short)%01%(upstream:track)%01%(committerdate:short)' 2>/dev/null > "$TMP/heads"
while IFS=$'\001' read -r b up track date; do
    [ -n "$b" ] || continue
    LOCAL_N=$((LOCAL_N+1))
    local_cmd="git -C \"$MAIN\" branch -D \"$b\""
    if protected_branch "$b"; then
        case "$b" in "$DEFAULT"|audit/*) continue ;; esac   # never listed, never offered
        if in_flight "$b"; then item br-protected "$b" "belongs to an issue in flight (in-flight.json)" ""
        elif [ "$b" = "$HEAD_BRANCH" ]; then item br-protected "$b" "checked out in the main checkout" ""; fi
        continue
    fi
    checked_out "$b" && continue   # listed with its worktree above
    st=$(pr_state "$b")
    if [ "${st%% *}" = "OPEN" ]; then item br-open-pr "$b" "open pull request #${st##* }" ""
    elif merged "$b"; then item br-merged "$b" "every commit is on $DEFAULT (last change $date)" "$local_cmd"
    elif [ "$track" = "[gone]" ]; then item br-gone "$b" "its remote branch $up was deleted (last change $date)" "$local_cmd"
    elif [ "${st%% *}" = "MERGED" ] || [ "${st%% *}" = "CLOSED" ]; then item br-pr-closed "$b" "pull request #${st##* } is ${st%% *} (last change $date)" "$local_cmd"
    else
        why="$(ahead "$b") commit(s) not on $DEFAULT, last change $date"; [ -z "$up" ] && why="$why, never pushed"
        item br-unmerged "$b" "$why" "$local_cmd"
    fi
done < "$TMP/heads"

# --- remote branches ------------------------------------------------------------------------------------
REMOTE_N=0
if [ -n "$REMOTE" ]; then
    g for-each-ref "refs/remotes/$REMOTE" --format='%(refname)%01%(committerdate:short)%01%(authorname)' 2>/dev/null > "$TMP/remotes"
    while IFS=$'\001' read -r ref date author; do
        [ -n "$ref" ] || continue
        rb="${ref#refs/remotes/}"           # origin/<branch>; refname:short would print origin/HEAD as plain origin
        [ "$rb" = "$REMOTE/HEAD" ] && continue
        REMOTE_N=$((REMOTE_N+1))
        b="${rb#$REMOTE/}"
        case "$b" in "$DEFAULT"|audit/*) continue ;; esac
        remote_cmd="git -C \"$MAIN\" push \"$REMOTE\" --delete \"$b\""
        if in_flight "$b"; then item rb-protected "$rb" "belongs to an issue in flight (in-flight.json)" ""; continue; fi
        st=$(pr_state "$b")
        if [ "${st%% *}" = "OPEN" ]; then item rb-open-pr "$rb" "open pull request #${st##* }" ""
        elif merged "$rb"; then item rb-merged "$rb" "every commit is on $DEFAULT (last change $date by $author)" "$remote_cmd"
        elif [ "${st%% *}" = "MERGED" ] || [ "${st%% *}" = "CLOSED" ]; then item rb-pr-closed "$rb" "pull request #${st##* } is ${st%% *} (last change $date by $author)" "$remote_cmd"
        else item rb-unmerged "$rb" "$(ahead "$rb") commit(s) not on $DEFAULT, no pull request known, last change $date by $author" "$remote_cmd"
        fi
    done < "$TMP/remotes"
fi

# --- the worktree root ----------------------------------------------------------------------------------
if [ -d "$WT_ROOT" ]; then
    for p in "$WT_ROOT"/* "$WT_ROOT"/.[!.]*; do
        [ -e "$p" ] || continue
        n=$(basename "$p")
        [ "$n" = "in-flight.json" ] && continue
        old=0; [ -n "$(find "$p" -maxdepth 0 -mtime +"$DAYS" 2>/dev/null)" ] && old=1
        if [ -d "$p" ]; then
            grep -qxF "$(norm "$p")" "$TMP/wt-paths" 2>/dev/null && continue   # one of ours, listed above
            if [ -f "$p/.git" ]; then
                gitdir=$(sed -n 's/^gitdir: //p' "$p/.git" 2>/dev/null | head -n1)
                case "$gitdir" in /*|[A-Za-z]:*) ;; *) gitdir="$p/$gitdir" ;; esac
                if [ -d "$gitdir" ]; then item root-other "$p" "a worktree of another repository" ""
                else item root-orphan "$p" "was a worktree, but the repository it belonged to no longer knows it" "rm -rf \"$p\""; fi
            elif [ -d "$p/.git" ]; then item root-other "$p" "a full clone of a repository" ""
            elif in_flight "$n"; then item root-other "$p" "folder of an issue in flight (in-flight.json)" ""
            elif [ "$old" = "1" ]; then item root-orphan "$p" "a plain folder, not a worktree, older than $DAYS days" "rm -rf \"$p\""
            else item root-recent "$p" "a plain folder changed in the last $DAYS days" ""; fi
        else
            if [ "$old" = "1" ]; then item root-file "$p" "a loose file older than $DAYS days" "rm -f \"$p\""
            else item root-recent "$p" "a loose file changed in the last $DAYS days" ""; fi
        fi
    done
else
    printf 'NOTE\tworktree root %s does not exist; nothing to check there\n' "$WT_ROOT"
fi

# --- print -----------------------------------------------------------------------------------------------
TOTAL=$((LOCAL_N+REMOTE_N)); OVER=no; [ "$TOTAL" -ge "$LIMIT" ] 2>/dev/null && OVER=yes
printf 'SCAN\tproject=%s default=%s remote=%s wt_root=%s fetched=%s pruned=%s gh=%s\n' "$MAIN" "$DEFAULT" "${REMOTE:-none}" "$WT_ROOT" "$FETCHED" "$PRUNED" "$GH"
printf 'COUNT\tlocal=%s remote=%s total=%s limit=%s over=%s\n' "$LOCAL_N" "$REMOTE_N" "$TOTAL" "$LIMIT" "$OVER"
[ "$GH" = "yes" ] || printf 'NOTE\tgh is missing or not signed in: pull request states are unknown, so a squash-merged branch is only recognised when its remote branch was deleted\n'
[ -z "$REMOTE" ] && printf 'NOTE\tno remote named origin: remote branches were not checked\n'
[ -n "$INFLIGHT" ] && printf 'NOTE\tissues in flight (never offered): %s\n' "$INFLIGHT"

O=0 A=0 K=0
emit() {  # id offer title
    local f="$TMP/g.$1" n
    [ -s "$f" ] || return 0
    n=$(wc -l < "$f" | tr -d ' ')
    case "$2" in yes) O=$((O+n)) ;; ask) A=$((A+n)) ;; *) K=$((K+n)) ;; esac
    printf 'GROUP\t%s\t%s\toffer=%s\t%s\n' "$1" "$n" "$2" "$3"
    cat "$f"
}
emit wt-prunable  yes "Worktree entries whose folder is already gone"
emit wt-done      yes "Worktrees whose branch is already on $DEFAULT"
emit wt-detached  yes "Temporary worktrees on no branch"
emit br-merged    yes "Local branches already on $DEFAULT"
emit br-gone      yes "Local branches whose remote branch was deleted"
emit br-pr-closed yes "Local branches whose pull request is merged or closed"
emit rb-merged    yes "Remote branches already on $DEFAULT"
emit rb-pr-closed yes "Remote branches whose pull request is merged or closed"
emit root-orphan  yes "Folders in the worktree root that are not worktrees"
emit root-file    yes "Loose files in the worktree root"
emit wt-active    ask "Worktrees with work that is not on $DEFAULT (deleting loses it)"
emit wt-dirty     ask "Worktrees with uncommitted changes (deleting loses them)"
emit br-unmerged  ask "Local branches with commits not on $DEFAULT (deleting loses them)"
emit rb-unmerged  ask "Remote branches with commits not on $DEFAULT and no pull request (deleting loses them, for everyone)"
emit wt-open-pr   no  "Worktrees with an open pull request (kept)"
emit br-open-pr   no  "Local branches with an open pull request (kept)"
emit rb-open-pr   no  "Remote branches with an open pull request (kept)"
emit wt-protected no  "Worktrees of issues in flight (kept)"
emit br-protected no  "Local branches checked out or in flight (kept)"
emit rb-protected no  "Remote branches of issues in flight (kept)"
emit root-recent  no  "Recent folders and files in the worktree root (kept)"
emit root-other   no  "Other repositories' checkouts in the worktree root (kept)"
printf 'SUMMARY\toffer=%s ask=%s keep=%s\n' "$O" "$A" "$K"
