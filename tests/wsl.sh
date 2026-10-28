#!/usr/bin/env bash
# tests/wsl.sh - the full suite on a Windows computer, split the way CI splits it: the whole suite inside WSL
# (Linux) on the commit checked out here, then the Windows part (tests/run.sh --windows) under Git Bash. The
# whole suite under Git Bash takes about 40 minutes, since every process start is slow there; in WSL about one.
#
# usage: bash tests/wsl.sh [--distro <name>]   run from Git Bash, after committing: WSL tests HEAD, never
#                                              uncommitted changes, so a dirty checkout is refused; the
#                                              distro needs git, jq and python3 (without jq the suite
#                                              skips the jq checks); exits 1 when either part fails, 2
#                                              when it cannot start

set -u

DISTRO=()
case "${1:-}" in
    "") ;;
    --distro) [ -n "${2:-}" ] || { echo "usage: bash tests/wsl.sh [--distro <name>]" >&2; exit 2; }; DISTRO=(-d "$2") ;;
    *) echo "usage: bash tests/wsl.sh [--distro <name>]" >&2; exit 2 ;;
esac

REPO="$(cd "$(dirname "$0")/.." && pwd)"
command -v wsl.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1 \
    || { echo "tests/wsl.sh: needs Git Bash on Windows with WSL; elsewhere run bash tests/run.sh" >&2; exit 2; }
[ -z "$(git -C "$REPO" status --porcelain)" ] \
    || { echo "tests/wsl.sh: commit first: WSL tests the commit checked out here, not uncommitted changes" >&2; exit 2; }
BRANCH="$(git -C "$REPO" symbolic-ref -q --short HEAD)" \
    || { echo "tests/wsl.sh: check out a branch first: WSL clones it by name" >&2; exit 2; }
HEAD_SHA="$(git -C "$REPO" rev-parse HEAD)"
# The repository itself, not this worktree: a worktree's .git file points at a Windows path that Linux git cannot follow.
COMMON="$(cd "$REPO" && cd "$(git rev-parse --git-common-dir)" && pwd)"
SRC="$(MSYS_NO_PATHCONV=1 wsl.exe "${DISTRO[@]}" --cd '~' -- wslpath -u "$(cygpath -m "$COMMON")" 2>/dev/null | tr -d '\r\0')"
case "$SRC" in /*) ;; *) echo "tests/wsl.sh: WSL could not run (no distro installed, or no such --distro)" >&2; exit 2 ;; esac
# The version checks compare with origin/main, as CI does after fetching it.
git -C "$REPO" fetch -q origin main 2>/dev/null \
    || echo "tests/wsl.sh: could not fetch origin/main: comparing with the last one fetched" >&2

echo "== the whole suite in WSL, on $BRANCH at ${HEAD_SHA:0:7}"
# Windows drives sit on WSL's PATH (/mnt/c/... by default, under whatever root wsl.conf sets): without them the
# suite cannot pick Windows' powershell.exe and feed it Linux paths. origin/main comes from this repository's copy.
MSYS_NO_PATHCONV=1 wsl.exe "${DISTRO[@]}" --cd '~' -- bash -s -- "$SRC" "$BRANCH" "$HEAD_SHA" <<'EOF'
src="$1" branch="$2" sha="$3"
drives="$(wslpath -u C:/)"; drives="${drives%/}"; drives="${drives%/*}/"
PATH="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vE "^${drives}[A-Za-z](/|\$)" | paste -sd: -)"; export PATH
dir="$(mktemp -d)"; trap 'rm -rf "$dir"' EXIT
git clone -q --branch "$branch" "$src" "$dir/orion" || exit 2
cd "$dir/orion" || exit 2
git fetch -q origin "+refs/remotes/origin/main:refs/remotes/origin/main" || exit 2
[ "$(git rev-parse HEAD)" = "$sha" ] || { echo "tests/wsl.sh: the clone is not at $sha" >&2; exit 2; }
bash tests/run.sh
EOF
LINUX=$?
[ "$LINUX" = 2 ] && { echo "tests/wsl.sh: the WSL part could not start" >&2; exit 2; }

echo "== the Windows part under Git Bash"
bash "$REPO/tests/run.sh" --windows
WINDOWS=$?

echo "wsl: $([ "$LINUX" = 0 ] && echo passed || echo "FAILED ($LINUX)"), windows part: $([ "$WINDOWS" = 0 ] && echo passed || echo FAILED)"
[ "$LINUX" = 0 ] && [ "$WINDOWS" = 0 ]
