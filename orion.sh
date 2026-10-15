#!/usr/bin/env bash
# orion - a repo-level utility framework for Claude Code projects.
#
# Everything orion ships is copied INTO the project (skills, a rules file, this
# script) and committed, so teammates get it with a plain git clone/pull. The
# only per-computer piece is the optional status line.
#
# Usage (run inside the project, or pass --project <dir>):
#   orion.sh init      [--source <git url|path>] [--ref <branch>] [--update-mode ask|auto|off]
#                      [--statusline|--no-statusline] [--force]
#   orion.sh update    [--force]        # fetch the latest orion and re-copy the files orion owns
#   orion.sh check     [--force]        # session-start hook: newer orion? too many branches? (once a day each)
#   orion.sh verify                     # mechanical post-install checks, one line per finding, no fixes
#   orion.sh status                     # what is installed, which version, which update mode
#   orion.sh uninstall [--yes]          # remove everything orion owns, keep everything yours
#   orion.sh help
#
# First-time bootstrap, no clone needed (run inside the project):
#   curl -fsSL https://raw.githubusercontent.com/nachogl1/orion/main/orion.sh | bash -s -- init
#
# After init, the next Claude Code session start is asked ONCE to run the
# /orion-verify skill: it runs `verify`, fixes what is mechanical, reviews
# CLAUDE.md against BASE_CLAUDE.md and the skills, and reports the rest.
#
# What orion owns in a project (overwritten on update, removed on uninstall):
#   .claude/skills/<skill>/           every folder carrying a `.orion-managed` marker
#   .claude/orion/orion.sh            this script
#   .claude/orion/BASE_CLAUDE.md      the mandatory rules, imported by CLAUDE.md
#   .claude/orion/VERSION             commit the files came from
#   .claude/orion/.orion-manifest     the list above
# What orion creates ONCE and never touches again (yours):
#   CLAUDE.md                         created with the project-specific slots if missing; otherwise
#                                     only the import line for BASE_CLAUDE.md is added at the top
#   .claude/orion/config.json         updateMode: ask | auto | off (chosen during init), source/ref, and
#                                     branchLimit (default 20, or off): the branch count at which the
#                                     session-start hook offers /clear-git-resources
#   .claude/settings.json             one SessionStart hook entry is added (removed on uninstall)

set -euo pipefail

ORION_DEFAULT_SOURCE="https://github.com/nachogl1/orion.git"
ORION_DEFAULT_REF="main"
MARKER=".orion-managed"
IMPORT_LINE="Mandatory rules, owned and refreshed by orion (never edit the copy): @.claude/orion/BASE_CLAUDE.md"
OLD_IMPORT_LINE="@.claude/orion/ORION.md"   # what orion wrote before the rules moved to BASE_CLAUDE.md
HOOK_NEEDLE="/.claude/orion/orion.sh"
HOOK_CMD='bash "${CLAUDE_PROJECT_DIR}/.claude/orion/orion.sh" check'
CHECK_INTERVAL_SECONDS=86400
BRANCH_LIMIT_DEFAULT=20

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
warn() { printf 'orion: %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

usage() { sed -n '2,37p' "$0" 2>/dev/null || true; exit 0; }

# The documented install is `curl ... | bash`, so stdin is the script itself: a question is still possible
# when the terminal can be opened directly (/dev/tty), which is what ask() reads from in that case.
is_tty() { [ -t 1 ] && { [ -t 0 ] || ( : </dev/tty ) 2>/dev/null; }; }
ask() {  # prompt -> sets $resp; reads from the terminal even when stdin is a pipe
    if [ -t 0 ]; then read -r -p "$1" resp; else read -r -p "$1" resp </dev/tty; fi
}

have() { command -v "$1" >/dev/null 2>&1; }

# Resolve the project root: --project > $CLAUDE_PROJECT_DIR > the project this
# script is installed in (<project>/.claude/orion/orion.sh) > git toplevel > cwd.
resolve_project() {
    local p="${1:-}" here
    if [ -z "$p" ] && [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then p="$CLAUDE_PROJECT_DIR"; fi
    if [ -z "$p" ]; then
        here="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" 2>/dev/null && pwd || true )"
        if [ -n "$here" ] && [ -f "$here/.orion-manifest" ] && [ "$(basename "$here")" = "orion" ]; then
            p="$( cd "$here/../.." && pwd )"
        fi
    fi
    if [ -z "$p" ]; then p="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; fi
    [ -d "$p" ] || die "project directory not found: $p"
    ( cd "$p" && pwd )
}

# Read a flat value from config.json without jq: a quoted string, or else a bare number.
config_get() {  # file key default
    local v=""
    if [ -f "$1" ]; then
        v=$(sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -n1)
        [ -n "$v" ] || v=$(sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" "$1" | head -n1)
    fi
    printf '%s' "${v:-$3}"
}

# The branch count the /clear-git-resources hook and scanner share: local branches plus
# remote-tracking branches, HEAD excluded, read from the local ref store (no network).
branch_count() {  # project-dir
    git -C "$1" for-each-ref --format='%(refname)' refs/heads refs/remotes 2>/dev/null | grep -vc '/HEAD$' || true
}

version_sha() { sed -n '1p' "$1" 2>/dev/null || true; }

short() { printf '%s' "${1:0:7}"; }

# Per-computer, per-project state that must never be committed (the daily
# update-check stamp, the one-shot "post-install check pending" marker).
cache_file() {  # suffix
    printf '%s/orion/%s.%s' "${XDG_CACHE_HOME:-$HOME/.cache}" "$(printf '%s' "$PROJECT" | cksum | cut -d' ' -f1)" "$1"
}

# The `name:` value of a skill's front matter (quotes stripped), or nothing.
skill_name() {  # SKILL.md
    awk 'NR==1 && $0 !~ /^---\r?$/ {exit} NR>1 && $0 ~ /^---\r?$/ {exit}
         /^name:/ { sub(/^name:[ \t]*/, ""); sub(/\r$/, ""); gsub(/^["'"'"']|["'"'"']$/, ""); print; exit }' "$1" 2>/dev/null
}

# Fetch orion into a temp dir. Sets SRC_DIR and SRC_SHA. If this script sits in
# an orion checkout (skills/ and baselines/ beside it) that checkout is used.
TMP_DIR=""
cleanup() { [ -n "$TMP_DIR" ] && rm -rf "$TMP_DIR" || true; }
trap cleanup EXIT

fetch_source() {  # source ref
    local here
    here="$( cd "$( dirname "${BASH_SOURCE[0]:-$0}" )" 2>/dev/null && pwd || true )"
    if [ -n "$here" ] && [ -d "$here/skills" ] && [ -d "$here/baselines" ] && [ -f "$here/orion.sh" ]; then
        SRC_DIR="$here"
        SRC_SHA="$(git -C "$here" rev-parse HEAD 2>/dev/null || printf 'local')"
        return
    fi
    have git || die "git is required to fetch orion"
    TMP_DIR="$(mktemp -d)"
    say "fetching orion ($2) from $1 ..."
    git clone --quiet --depth 1 --branch "$2" "$1" "$TMP_DIR/orion" 2>/dev/null \
        || die "could not fetch orion from $1 (ref $2)"
    SRC_DIR="$TMP_DIR/orion"
    SRC_SHA="$(git -C "$SRC_DIR" rev-parse HEAD)"
}

latest_sha() {  # source ref -> prints sha or nothing
    local out=""
    if have timeout; then
        out=$(timeout 15 git ls-remote "$1" "refs/heads/$2" 2>/dev/null || true)
    else
        out=$(git ls-remote "$1" "refs/heads/$2" 2>/dev/null || true)
    fi
    printf '%s' "$out" | cut -f1 | head -n1
}

# --------------------------------------------------------------------------
# JSON edits on settings files (jq > python3 > powershell > manual note)
# --------------------------------------------------------------------------
json_tool() {
    # python is probed by running it: on Windows a "python3" alias stub can exist without a real install
    if [ -n "${ORION_JSON_TOOL:-}" ]; then echo "$ORION_JSON_TOOL"
    elif have jq; then echo jq
    elif python3 -c 'import json' >/dev/null 2>&1; then echo python3
    elif python -c 'import json' >/dev/null 2>&1; then echo python
    elif have powershell.exe; then echo powershell
    else echo none; fi
}

json_valid() {  # file -> 0 when it parses (or when no JSON tool exists to tell)
    local tool; tool=$(json_tool)
    case "$tool" in
        jq) jq empty "$1" >/dev/null 2>&1 ;;
        python3|python) "$tool" -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8-sig"))' "$1" >/dev/null 2>&1 ;;
        powershell) powershell.exe -NoProfile -NonInteractive -Command "Get-Content -Raw '$(cygpath -w "$1" 2>/dev/null || printf '%s' "$1")' | ConvertFrom-Json | Out-Null" >/dev/null 2>&1 ;;
        *) return 0 ;;
    esac
}

settings_add_hook() {  # settings-file
    local f="$1" tool
    mkdir -p "$(dirname "$f")"
    if [ -f "$f" ] && grep -qF "$HOOK_NEEDLE" "$f"; then
        say "  =    update check hook already present in ${f#"$PROJECT"/}"
        return
    fi
    [ -f "$f" ] || printf '{}\n' > "$f"
    tool=$(json_tool)
    case "$tool" in
        jq)
            local tmp; tmp=$(mktemp)
            jq --arg cmd "$HOOK_CMD" '.hooks = (.hooks // {}) | .hooks.SessionStart = ((.hooks.SessionStart // []) + [{matcher:"startup|resume", hooks:[{type:"command", command:$cmd, timeout:20}]}])' "$f" > "$tmp" && mv "$tmp" "$f" ;;
        python3|python)
            "$tool" - "$f" "$HOOK_CMD" <<'PY'
import json, sys
f, cmd = sys.argv[1], sys.argv[2]
d = json.load(open(f, encoding="utf-8"))
h = d.setdefault("hooks", {})
h.setdefault("SessionStart", []).append({"matcher": "startup|resume", "hooks": [{"type": "command", "command": cmd, "timeout": 20}]})
json.dump(d, open(f, "w", encoding="utf-8"), indent=2)
open(f, "a", encoding="utf-8").write("\n")
PY
            ;;
        powershell)
            powershell.exe -NoProfile -NonInteractive -Command "
                \$f = '$(cygpath -w "$f" 2>/dev/null || printf '%s' "$f")'; \$cmd = '$HOOK_CMD'
                \$d = Get-Content -Raw \$f | ConvertFrom-Json
                if (-not \$d.PSObject.Properties['hooks']) { \$d | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject) }
                if (-not \$d.hooks.PSObject.Properties['SessionStart']) { \$d.hooks | Add-Member -NotePropertyName SessionStart -NotePropertyValue @() }
                \$entry = [PSCustomObject]@{ matcher = 'startup|resume'; hooks = @([PSCustomObject]@{ type = 'command'; command = \$cmd; timeout = 20 }) }
                \$d.hooks.SessionStart = @(\$d.hooks.SessionStart) + @(\$entry)
                [IO.File]::WriteAllText(\$f, (\$d | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
            " >/dev/null ;;
        *)
            warn "no jq/python/powershell found - add this SessionStart hook to $f by hand:"
            warn "  {\"hooks\":{\"SessionStart\":[{\"matcher\":\"startup|resume\",\"hooks\":[{\"type\":\"command\",\"command\":\"$HOOK_CMD\",\"timeout\":20}]}]}}"
            return ;;
    esac
    say "  +    update check hook in ${f#"$PROJECT"/}"
}

settings_remove_hook() {  # settings-file
    local f="$1" tool
    [ -f "$f" ] && grep -qF "$HOOK_NEEDLE" "$f" || return 0
    tool=$(json_tool)
    case "$tool" in
        jq)
            local tmp; tmp=$(mktemp)
            jq '.hooks.SessionStart = [ (.hooks.SessionStart // [])[] | select(([.hooks[]?.command // ""] | any(contains("/.claude/orion/orion.sh"))) | not) ] | if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end | if (.hooks | length) == 0 then del(.hooks) else . end' "$f" > "$tmp" && mv "$tmp" "$f" ;;
        python3|python)
            "$tool" - "$f" <<'PY'
import json, sys
f = sys.argv[1]
d = json.load(open(f, encoding="utf-8"))
ss = d.get("hooks", {}).get("SessionStart", [])
ss = [g for g in ss if not any('/.claude/orion/orion.sh' in (x.get("command") or "") for x in g.get("hooks", []))]
if ss: d["hooks"]["SessionStart"] = ss
else:
    d.get("hooks", {}).pop("SessionStart", None)
    if not d.get("hooks"): d.pop("hooks", None)
json.dump(d, open(f, "w", encoding="utf-8"), indent=2)
open(f, "a", encoding="utf-8").write("\n")
PY
            ;;
        powershell)
            powershell.exe -NoProfile -NonInteractive -Command "
                \$f = '$(cygpath -w "$f" 2>/dev/null || printf '%s' "$f")'
                \$d = Get-Content -Raw \$f | ConvertFrom-Json
                \$keep = @(\$d.hooks.SessionStart | Where-Object { -not (\$_.hooks | Where-Object { \$_.command -like '*/.claude/orion/orion.sh*' }) })
                if (\$keep.Count -gt 0) { \$d.hooks.SessionStart = \$keep } else { \$d.hooks.PSObject.Properties.Remove('SessionStart') }
                if (@(\$d.hooks.PSObject.Properties).Count -eq 0) { \$d.PSObject.Properties.Remove('hooks') }
                [IO.File]::WriteAllText(\$f, (\$d | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
            " >/dev/null ;;
        *)
            warn "no jq/python/powershell found - remove the orion SessionStart hook from $f by hand"
            return ;;
    esac
    say "  -    update check hook removed from ${f#"$PROJECT"/}"
}

settings_set_statusline() {  # settings-file command
    local f="$1" cmd="$2" tool
    mkdir -p "$(dirname "$f")"
    [ -f "$f" ] || printf '{}\n' > "$f"
    tool=$(json_tool)
    case "$tool" in
        jq)
            local tmp; tmp=$(mktemp)
            jq --arg cmd "$cmd" '.statusLine = {type: "command", command: $cmd}' "$f" > "$tmp" && mv "$tmp" "$f" ;;
        python3|python)
            "$tool" - "$f" "$cmd" <<'PY'
import json, sys
f, cmd = sys.argv[1], sys.argv[2]
d = json.load(open(f, encoding="utf-8"))
d["statusLine"] = {"type": "command", "command": cmd}
json.dump(d, open(f, "w", encoding="utf-8"), indent=2)
open(f, "a", encoding="utf-8").write("\n")
PY
            ;;
        powershell)
            powershell.exe -NoProfile -NonInteractive -Command "
                \$f = '$(cygpath -w "$f" 2>/dev/null || printf '%s' "$f")'; \$cmd = '$cmd'
                \$d = Get-Content -Raw \$f | ConvertFrom-Json
                \$sl = [PSCustomObject]@{ type = 'command'; command = \$cmd }
                if (\$d.PSObject.Properties['statusLine']) { \$d.statusLine = \$sl } else { \$d | Add-Member -NotePropertyName statusLine -NotePropertyValue \$sl }
                [IO.File]::WriteAllText(\$f, (\$d | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
            " >/dev/null ;;
        *)
            warn "no jq/python/powershell found - set this in $f by hand:"
            warn "  {\"statusLine\":{\"type\":\"command\",\"command\":\"$cmd\"}}"
            return ;;
    esac
    say "statusLine configured in $f"
}

# --------------------------------------------------------------------------
# apply: copy everything orion owns from SRC_DIR into the project
# --------------------------------------------------------------------------
copy_managed() {  # src dst
    rm -rf "$2"
    mkdir -p "$2"
    # marker first: an interrupted copy still looks orion-managed and gets redone next time
    printf '%s' "orion" > "$2/$MARKER"
    cp -R "$1"/. "$2"
}

apply_skills() {  # mode(init|update) force(0|1)
    local mode="$1" force="$2" skills_dir="$PROJECT/.claude/skills" src_skills="$SRC_DIR/skills"
    local added=0 updated=0 pruned=0 skipped=0 entry name skill dest is_ours resp
    mkdir -p "$skills_dir"
    shopt -s nullglob
    for entry in "$skills_dir"/*/; do
        name=$(basename "$entry")
        [ -f "${entry%/}/$MARKER" ] || continue
        if [ ! -d "$src_skills/$name" ]; then
            rm -rf "${entry%/}"
            say "  -    $name (orion no longer ships it)"
            pruned=$((pruned+1))
        fi
    done
    for skill in "$src_skills"/*/; do
        name=$(basename "$skill"); dest="$skills_dir/$name"
        is_ours=0; [ -f "$dest/$MARKER" ] && is_ours=1
        if [ -e "$dest" ] && [ "$is_ours" != "1" ]; then
            if [ "$mode" = "update" ] || { [ "$force" != "1" ] && ! is_tty; }; then
                say "  skip $name (exists and is not an orion copy)"; skipped=$((skipped+1)); continue
            fi
            if [ "$force" != "1" ]; then
                ask "  !  $name exists and is not an orion copy. Overwrite? [y/N] "
                if [[ ! "$resp" =~ ^[Yy]$ ]]; then say "  skip $name"; skipped=$((skipped+1)); continue; fi
            fi
        fi
        copy_managed "${skill%/}" "$dest"
        if [ "$is_ours" = "1" ]; then say "  ~    $name"; updated=$((updated+1)); else say "  +    $name"; added=$((added+1)); fi
    done
    shopt -u nullglob
    say "  skills: $added added, $updated updated, $pruned removed, $skipped skipped"
}

apply_core() {  # source ref update-mode
    local dir="$PROJECT/.claude/orion" tmp mode="${3:-ask}"
    mkdir -p "$dir"
    # orion.sh may be the script currently running: write beside, then mv (atomic).
    tmp="$dir/.orion.sh.new"; cp "$SRC_DIR/orion.sh" "$tmp"; chmod +x "$tmp"; mv -f "$tmp" "$dir/orion.sh"
    cp "$SRC_DIR/baselines/BASE_CLAUDE.md" "$dir/BASE_CLAUDE.md"
    [ -f "$dir/ORION.md" ] && { rm -f "$dir/ORION.md"; say "  -    .claude/orion/ORION.md (the rules now live in BASE_CLAUDE.md)"; }
    printf '%s\n%s\n%s\n' "$SRC_SHA" "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$dir/VERSION"
    printf '%s\n' "orion.sh" "BASE_CLAUDE.md" "VERSION" ".orion-manifest" > "$dir/.orion-manifest"
    if [ ! -f "$dir/config.json" ]; then
        printf '{\n  "updateMode": "%s",\n  "source": "%s",\n  "ref": "%s",\n  "branchLimit": %s\n}\n' "$mode" "$1" "$2" "$BRANCH_LIMIT_DEFAULT" > "$dir/config.json"
        say "  +    .claude/orion/config.json (yours: updateMode $mode, edit to ask | auto | off; branchLimit $BRANCH_LIMIT_DEFAULT, a number or off)"
    fi
    say "  ~    .claude/orion/{orion.sh, BASE_CLAUDE.md, VERSION} @ $(short "$SRC_SHA")"
}

# The project's own CLAUDE.md: created once with the project-specific slots the
# mandatory rules rely on (see the last section of BASE_CLAUDE.md), never
# overwritten. An existing CLAUDE.md only gets the import line at the top.
write_claude_md_starter() {  # file
    cat > "$1" <<EOF
$IMPORT_LINE

# CLAUDE.md — <project name>

Project-specific facts the mandatory rules rely on. Fill every \`<angle-bracket>\` slot; delete a line the project
has no use for. A rule written here must not contradict the mandatory rules.

## Build and test commands

| Purpose | Command |
|---|---|
| Build | \`TBD\` |
| **The full suite** | \`TBD\` |
| One file | \`TBD\` |
| One test | \`TBD\` |
| Typecheck / static analysis | \`TBD\` |
| Lint | \`TBD\` |
| Deterministic checks on generated output (if any) | \`TBD\` |
| Dev server (if the review surface needs one) | \`TBD\` |

## Stack and layout

- Stack: **<language and version, pinned in <pin file>>**, **<test framework>**; CI runs on <runner>.
- Layout: \`<application code path>\` and \`<test code path>\`. Skip-count baseline: <N>.

## Worktrees

- Worktree root (outside the project): \`<worktree root>\`. Port = \`<base port> + issue number\`, written to the
  worktree's \`.env\` as \`<port variable>\`.

## Boundaries

- Deploys to: <environment>, from \`main\`.
- External read-only repositories: <none, or list them with their work-item key format>.
- Sensitive data classes that never enter the repository: <customer records, partner-owned schemas, …>.
- Boundaries an agent must not move: <e.g. "AI is a build-time tool; nothing it produces executes at runtime">.
- Working language for code, comments, commits, issues and docs: <language>.

## Pending until PRD v1

| # | File and section | Question | Decided by |
|---|---|---|---|
| P1 | \`CLAUDE.md\` build and test commands | <e.g. Which stack, and so which build/test/lint commands?> | <role> |
EOF
}

apply_claude_md() {
    local f="$PROJECT/CLAUDE.md" tmp
    if [ ! -f "$f" ]; then
        write_claude_md_starter "$f"
        say "  +    CLAUDE.md (project slots to fill in; it is yours now and imports the mandatory rules)"
    elif grep -qxF "$OLD_IMPORT_LINE" "$f"; then
        tmp=$(mktemp); sed "s|^$OLD_IMPORT_LINE\$|$IMPORT_LINE|" "$f" > "$tmp"; mv "$tmp" "$f"
        say "  ~    CLAUDE.md (import line now points at BASE_CLAUDE.md; nothing else touched)"
    elif ! grep -qxF "$IMPORT_LINE" "$f"; then
        tmp=$(mktemp); { printf '%s\n\n' "$IMPORT_LINE"; cat "$f"; } > "$tmp"; mv "$tmp" "$f"
        say "  ~    CLAUDE.md (import line added at the top; nothing else touched)"
    else
        say "  =    CLAUDE.md (already imports the mandatory rules)"
    fi
}

# Earlier orion versions copied skills to ~/.claude/skills (user level). A
# user-level copy with the same name as a project copy is confusing, and those
# copies carry orion's own marker, so init retires them.
retire_user_level_copies() {
    local entry
    shopt -s nullglob
    for entry in "$HOME"/.claude/skills/*/; do
        if [ -f "${entry%/}/$MARKER" ]; then
            rm -rf "${entry%/}"
            say "  -    ~/.claude/skills/$(basename "$entry") (old user-level orion copy retired)"
        fi
    done
    shopt -u nullglob
}

# --------------------------------------------------------------------------
# status line (optional, per computer, copied ONCE then yours)
# --------------------------------------------------------------------------
install_statusline() {  # force
    local src="$SRC_DIR/baselines/statusline" dest="$HOME/.claude/statusline" exists=0
    [ -d "$src" ] || { warn "status line baseline not found in source"; return; }
    [ -f "$dest/statusline.sh" ] && exists=1
    if [ "$exists" = "1" ] && [ "$1" != "1" ]; then
        say "  =    statusline (already installed - yours to edit; delete ~/.claude/statusline or pass --force to re-seed)"
    else
        rm -rf "$dest"; mkdir -p "$dest"; cp -R "$src"/. "$dest"
        printf '%s' "orion" > "$dest/.orion-baseline"
        say "  +    statusline -> ~/.claude/statusline"
    fi
    settings_set_statusline "$HOME/.claude/settings.json" "bash \"$dest/statusline.sh\""
    if have npx && have jq; then
        say "warming the month-to-date cost cache (one-time, best effort)..."
        ( since=$(date +%Y%m01); cache="$HOME/.cache/claude-statusline/cost-mtd.txt"
          mkdir -p "$(dirname "$cache")" 2>/dev/null
          total=$(npx -y ccusage daily --json --since "$since" 2>/dev/null | jq -r '.totals.totalCost // empty')
          [ -n "$total" ] && printf '%.2f' "$total" > "$cache" ) || true
    fi
}

# --------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------
cmd_init() {
    local source="$ORION_DEFAULT_SOURCE" ref="$ORION_DEFAULT_REF" force=0 statusline="prompt" project="" resp mode=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --source) source="$2"; shift 2 ;;
            --ref) ref="$2"; shift 2 ;;
            --update-mode) mode="$2"; shift 2 ;;
            --project) project="$2"; shift 2 ;;
            --force) force=1; shift ;;
            --statusline) statusline=yes; shift ;;
            --no-statusline) statusline=no; shift ;;
            -h|--help) usage ;;
            *) die "unknown option for init: $1" ;;
        esac
    done
    PROJECT="$(resolve_project "$project")"
    local cfg="$PROJECT/.claude/orion/config.json"
    if [ -f "$cfg" ]; then
        source="$(config_get "$cfg" source "$source")"; ref="$(config_get "$cfg" ref "$ref")"
    fi
    case "$mode" in ""|ask|auto|off) ;; *) die "--update-mode must be ask, auto or off (got: $mode)" ;; esac
    say "orion init -> $PROJECT"
    # config.json is written once and never touched again, so the update mode is chosen here.
    if [ -z "$mode" ] && [ ! -f "$cfg" ] && is_tty; then
        say "When a newer orion exists, what should happen at session start?"
        say "  1) ask   - offer the update and let you say yes or no (default)"
        say "  2) auto  - update by itself and tell you in one line"
        say "  3) off   - never check"
        ask "Choose [1/2/3] (Enter = ask): "
        case "$resp" in 2|auto) mode=auto ;; 3|off) mode=off ;; *) mode=ask ;; esac
    fi
    fetch_source "$source" "$ref"
    retire_user_level_copies
    apply_skills init "$force"
    apply_core "$source" "$ref" "${mode:-ask}"
    apply_claude_md
    settings_add_hook "$PROJECT/.claude/settings.json"
    if [ "$statusline" = "prompt" ]; then
        statusline=no
        if is_tty; then
            ask "Also install the orion status line for this computer (~/.claude/statusline, optional)? [y/N] "
            [[ "$resp" =~ ^[Yy]$ ]] && statusline=yes
        fi
    fi
    [ "$statusline" = "yes" ] && install_statusline "$force"
    # One-shot: the next session start asks Claude Code to run the post-install check.
    pending="$(cache_file verify-pending)"
    mkdir -p "$(dirname "$pending")" 2>/dev/null && printf '%s' "$(date +%s)" > "$pending" || true
    say ""
    say "done. Review with 'git status', then commit the new files on a branch so your team gets them."
    say "Next: in Claude Code, run /orion-verify. It checks that CLAUDE.md, the imported rules, the skills and the"
    say "settings fit together after the install, fixes what is mechanical and reports the rest. If you skip it,"
    say "the next session start asks for it once."
}

cmd_update() {
    local force=0 project="" quiet=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --project) project="$2"; shift 2 ;;
            --force) force=1; shift ;;
            --quiet) quiet=1; shift ;;
            -h|--help) usage ;;
            *) die "unknown option for update: $1" ;;
        esac
    done
    PROJECT="$(resolve_project "$project")"
    local dir="$PROJECT/.claude/orion" cfg="$PROJECT/.claude/orion/config.json" source ref current
    [ -f "$dir/VERSION" ] || die "orion is not installed in $PROJECT (run: orion.sh init)"
    source="$(config_get "$cfg" source "$ORION_DEFAULT_SOURCE")"; ref="$(config_get "$cfg" ref "$ORION_DEFAULT_REF")"
    current="$(version_sha "$dir/VERSION")"
    fetch_source "$source" "$ref"
    if [ "$SRC_SHA" = "$current" ] && [ "$force" != "1" ]; then
        say "orion is already at $(short "$current") - nothing to do (pass --force to re-copy anyway)"
        return
    fi
    say "orion update $(short "$current") -> $(short "$SRC_SHA") in $PROJECT"
    apply_skills update 0
    apply_core "$source" "$ref"
    apply_claude_md
    settings_add_hook "$PROJECT/.claude/settings.json"
    if [ "$quiet" != "1" ]; then
        say "done. Review with 'git status' / 'git diff', then commit on a branch so your team gets it."
        say "If .claude/orion/BASE_CLAUDE.md changed, re-read CLAUDE.md for rules that now contradict it and fix them in the same commit."
    fi
}

# Session-start hook. Never fails the session: any problem -> silent exit 0.
cmd_check() {
    local force=0 project=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --project) project="$2"; shift 2 ;;
            --force) force=1; shift ;;
            *) shift ;;
        esac
    done
    PROJECT="$(resolve_project "$project")" || exit 0
    local dir="$PROJECT/.claude/orion" now ctx tidy pending
    [ -f "$dir/VERSION" ] || exit 0
    # A fresh init leaves a one-shot marker: ask for the post-install check instead of an update.
    pending="$(cache_file verify-pending)"
    if [ -f "$pending" ]; then
        rm -f "$pending" 2>/dev/null || true
        if [ -f "$PROJECT/.claude/skills/orion-verify/SKILL.md" ]; then
            ctx="orion was just installed in this project and its post-install check has not run yet. Before anything else, run the /orion-verify skill (.claude/skills/orion-verify/SKILL.md) exactly as written: it checks that CLAUDE.md, the imported BASE_CLAUDE.md, the skills under .claude/skills and the settings are consistent after the install, fixes what is mechanical, asks before touching anything the project owns, and reports in a few lines. Then continue with the user's request."
            printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ctx"
        fi
        exit 0
    fi
    now=$(date +%s)
    ctx="$(check_update_ctx "$force" "$now")"
    tidy="$(check_branches_ctx "$force" "$now")"
    if [ -n "$ctx" ] && [ -n "$tidy" ]; then ctx="$ctx After that: $tidy"; else ctx="$ctx$tidy"; fi
    [ -n "$ctx" ] || exit 0
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ctx"
}

# The daily update check. Prints the context for Claude Code, or nothing when there is nothing to say.
check_update_ctx() {  # force now
    local cfg="$PROJECT/.claude/orion/config.json" dir="$PROJECT/.claude/orion" mode source ref current latest stamp last
    mode="$(config_get "$cfg" updateMode ask)"
    [ "$mode" = "off" ] && return 0
    stamp="$(cache_file last-check)"
    if [ "$1" != "1" ] && [ -f "$stamp" ]; then
        last=$(cat "$stamp" 2>/dev/null || echo 0)
        [ $(($2 - last)) -lt "$CHECK_INTERVAL_SECONDS" ] && return 0
    fi
    mkdir -p "$(dirname "$stamp")" 2>/dev/null && printf '%s' "$2" > "$stamp" || true
    source="$(config_get "$cfg" source "$ORION_DEFAULT_SOURCE")"; ref="$(config_get "$cfg" ref "$ORION_DEFAULT_REF")"
    current="$(version_sha "$dir/VERSION")"
    latest="$(latest_sha "$source" "$ref")"
    [ -n "$latest" ] || return 0
    [ "$latest" = "$current" ] && return 0
    case "$mode" in
        auto)
            if cmd_update --project "$PROJECT" --quiet >/dev/null 2>&1; then
                printf '%s' "orion (the repo-level utility framework in .claude/orion) was updated automatically from $(short "$current") to $(short "$latest"), as the project's updateMode is 'auto'. Tell the user in one line, and remind them to review 'git status' and commit the changed orion files on a branch."
            else
                printf '%s' "orion tried to update itself automatically ($(short "$current") -> $(short "$latest")) and failed. Tell the user in one line that running 'bash .claude/orion/orion.sh update' by hand will show the error."
            fi ;;
        *)
            printf '%s' "A newer orion is available for this project ($(short "$current") -> $(short "$latest")). Before anything else, ask the user with the AskUserQuestion tool whether to update orion now (options: 'Update now' recommended, 'Not now'). If they say yes, run 'bash .claude/orion/orion.sh update' from the project root, summarise the changed files in one line, and remind them to commit on a branch. If they say no, continue with their request and do not mention it again this session." ;;
    esac
}

# The daily branch-count check behind /clear-git-resources: only when that skill is installed, only
# from the local ref store (no network), silent below the limit. Prints the context or nothing.
check_branches_ctx() {  # force now
    local cfg="$PROJECT/.claude/orion/config.json" limit stamp last n
    [ -f "$PROJECT/.claude/skills/clear-git-resources/SKILL.md" ] || return 0
    have git || return 0
    limit="$(config_get "$cfg" branchLimit "$BRANCH_LIMIT_DEFAULT")"
    case "$limit" in off|0) return 0 ;; *[!0-9]*|"") limit="$BRANCH_LIMIT_DEFAULT" ;; esac
    stamp="$(cache_file branches-check)"
    if [ "$1" != "1" ] && [ -f "$stamp" ]; then
        last=$(cat "$stamp" 2>/dev/null || echo 0)
        [ $(($2 - last)) -lt "$CHECK_INTERVAL_SECONDS" ] && return 0
    fi
    n="$(branch_count "$PROJECT")"
    [ "${n:-0}" -ge "$limit" ] 2>/dev/null || return 0
    mkdir -p "$(dirname "$stamp")" 2>/dev/null && printf '%s' "$2" > "$stamp" || true
    printf '%s' "This project has $n git branches (local plus remote-tracking), at or above the limit of $limit set as branchLimit in .claude/orion/config.json. Before anything else, ask the user with the AskUserQuestion tool whether to tidy up now (options: 'Show me what can go' recommended, 'Not now'). If they say yes, run the /clear-git-resources skill (.claude/skills/clear-git-resources/SKILL.md) exactly as written: it lists the stale worktrees, branches and leftover files in plain words and deletes only what the user agrees to. If they say no, continue with their request and do not mention it again this session."
}

cmd_status() {
    local project=""
    while [ $# -gt 0 ]; do case "$1" in --project) project="$2"; shift 2 ;; *) shift ;; esac; done
    PROJECT="$(resolve_project "$project")"
    local dir="$PROJECT/.claude/orion" cfg="$PROJECT/.claude/orion/config.json" n=0 entry
    if [ ! -f "$dir/VERSION" ]; then say "orion is not installed in $PROJECT"; return; fi
    say "project:    $PROJECT"
    say "version:    $(short "$(version_sha "$dir/VERSION")") ($(sed -n '2p' "$dir/VERSION") @ $(sed -n '3p' "$dir/VERSION"))"
    say "source:     $(config_get "$cfg" source "$ORION_DEFAULT_SOURCE")"
    say "updateMode: $(config_get "$cfg" updateMode ask)   (edit .claude/orion/config.json: ask | auto | off)"
    say "branchLimit: $(config_get "$cfg" branchLimit "$BRANCH_LIMIT_DEFAULT")   (branches now: $(branch_count "$PROJECT"); the hook offers /clear-git-resources at the limit; a number or off)"
    shopt -s nullglob
    for entry in "$PROJECT"/.claude/skills/*/; do
        [ -f "${entry%/}/$MARKER" ] && { say "skill:      $(basename "$entry")"; n=$((n+1)); }
    done
    shopt -u nullglob
    say "skills:     $n orion-managed"
    grep -qxF "$IMPORT_LINE" "$PROJECT/CLAUDE.md" 2>/dev/null && say "CLAUDE.md:  imports the mandatory rules" || say "CLAUDE.md:  does NOT import the mandatory rules (run: orion.sh update)"
    grep -qF "$HOOK_NEEDLE" "$PROJECT/.claude/settings.json" 2>/dev/null && say "hook:       update check installed" || say "hook:       update check NOT installed"
}

cmd_uninstall() {
    local yes=0 project="" resp entry f line tmp
    while [ $# -gt 0 ]; do
        case "$1" in
            --project) project="$2"; shift 2 ;;
            --yes|-y) yes=1; shift ;;
            -h|--help) usage ;;
            *) die "unknown option for uninstall: $1" ;;
        esac
    done
    PROJECT="$(resolve_project "$project")"
    local dir="$PROJECT/.claude/orion"
    if [ "$yes" != "1" ]; then
        is_tty || die "refusing to uninstall without --yes in a non-interactive shell"
        ask "Remove everything orion owns from $PROJECT (your CLAUDE.md rules and your own skills stay)? [y/N] "
        [[ "$resp" =~ ^[Yy]$ ]] || { say "aborted"; return; }
    fi
    shopt -s nullglob
    for entry in "$PROJECT"/.claude/skills/*/; do
        [ -f "${entry%/}/$MARKER" ] && { rm -rf "${entry%/}"; say "  -    skill $(basename "$entry")"; }
    done
    shopt -u nullglob
    rmdir "$PROJECT/.claude/skills" 2>/dev/null || true
    if [ -f "$dir/.orion-manifest" ]; then
        while IFS= read -r line; do [ -n "$line" ] && rm -f "$dir/$line"; done < "$dir/.orion-manifest"
        rm -f "$dir/.orion-manifest"
    fi
    rm -f "$dir/config.json"
    rmdir "$dir" 2>/dev/null && say "  -    .claude/orion" || warn "left .claude/orion in place (it holds files orion did not create)"
    f="$PROJECT/CLAUDE.md"
    if [ -f "$f" ] && { grep -qxF "$IMPORT_LINE" "$f" || grep -qxF "$OLD_IMPORT_LINE" "$f"; }; then
        tmp=$(mktemp); grep -vxF "$IMPORT_LINE" "$f" | grep -vxF "$OLD_IMPORT_LINE" | sed '1{/^$/d;}' > "$tmp"; mv "$tmp" "$f"
        say "  ~    CLAUDE.md (import line removed; your rules untouched)"
    fi
    settings_remove_hook "$PROJECT/.claude/settings.json"
    rm -f "$(cache_file verify-pending)" 2>/dev/null || true
    say "done. The status line (if installed) is a per-computer copy under ~/.claude/statusline and was left alone."
}

# Mechanical post-install checks: one line per finding, never a fix. Exit 1 when
# anything FAILs. The /orion-verify skill runs this first, then fixes and reviews.
# Clears the one-shot marker that init leaves for the session-start hook.
VERIFY_FAIL=0; VERIFY_WARN=0
v_ok()   { say "  ok    $1: $2"; }
v_warn() { say "  WARN  $1: $2"; VERIFY_WARN=$((VERIFY_WARN+1)); }
v_fail() { say "  FAIL  $1: $2"; VERIFY_FAIL=$((VERIFY_FAIL+1)); }

cmd_verify() {
    local project=""
    while [ $# -gt 0 ]; do case "$1" in --project) project="$2"; shift 2 ;; -h|--help) usage ;; *) die "unknown option for verify: $1" ;; esac; done
    PROJECT="$(resolve_project "$project")"
    local dir="$PROJECT/.claude/orion" cfg="$PROJECT/.claude/orion/config.json" skills="$PROJECT/.claude/skills"
    local claude="$PROJECT/CLAUDE.md" settings="$PROJECT/.claude/settings.json" base="$PROJECT/.claude/orion/BASE_CLAUDE.md"
    local f n mode entry name sname ours names="" dups="" checks="" ref p slots
    rm -f "$(cache_file verify-pending)" 2>/dev/null || true
    say "orion verify -> $PROJECT"

    # 1. the files orion owns
    n=""
    for f in orion.sh BASE_CLAUDE.md VERSION .orion-manifest config.json; do [ -f "$dir/$f" ] || n="$n $f"; done
    if [ -z "$n" ]; then v_ok core-files ".claude/orion/{orion.sh, BASE_CLAUDE.md, VERSION, .orion-manifest, config.json} present"
    else v_fail core-files "missing in .claude/orion:$n (fix: bash .claude/orion/orion.sh update --force, or init if orion.sh itself is gone)"; fi
    mode="$(config_get "$cfg" updateMode ask)"
    case "$mode" in ask|auto|off) v_ok config-update-mode "updateMode is '$mode'" ;;
        *) v_fail config-update-mode "updateMode is '$mode' in .claude/orion/config.json; must be ask, auto or off" ;; esac
    mode="$(config_get "$cfg" branchLimit "$BRANCH_LIMIT_DEFAULT")"
    case "$mode" in
        off) v_ok config-branch-limit "branchLimit is off (the hook never offers /clear-git-resources)" ;;
        ""|*[!0-9]*) v_fail config-branch-limit "branchLimit is '$mode' in .claude/orion/config.json; must be a whole number or off" ;;
        *) v_ok config-branch-limit "branchLimit is $mode (branches now: $(branch_count "$PROJECT"))" ;;
    esac
    [ ! -f "$cfg" ] || json_valid "$cfg" || v_fail config-json ".claude/orion/config.json is not valid JSON"

    # 2. CLAUDE.md and the rules it imports
    if [ ! -f "$claude" ]; then
        v_fail claude-md "CLAUDE.md is missing (fix: bash .claude/orion/orion.sh update --force writes the starter)"
    else
        n=$(grep -cxF "$IMPORT_LINE" "$claude" || true)
        case "$n" in
            1) v_ok claude-md-import "CLAUDE.md imports .claude/orion/BASE_CLAUDE.md once" ;;
            0) v_fail claude-md-import "CLAUDE.md does not import the mandatory rules (fix: add this line at the top: $IMPORT_LINE)" ;;
            *) v_fail claude-md-import "CLAUDE.md carries the import line $n times (fix: keep the first, delete the others)" ;;
        esac
        grep -qxF "$OLD_IMPORT_LINE" "$claude" && v_fail claude-md-old-import "CLAUDE.md still imports the retired ORION.md (fix: delete that line; the BASE_CLAUDE.md import replaces it)"
        slots=$(grep -cE '`TBD`|<[a-z][^<>]*>' "$claude" || true)
        [ "$slots" -gt 0 ] 2>/dev/null && v_warn claude-md-slots "CLAUDE.md has $slots line(s) with an unfilled slot (TBD or <placeholder>); the rules that rely on them cannot run until they are filled"
        while IFS= read -r p; do
            [ -n "$p" ] && [ ! -e "$PROJECT/$p" ] && v_warn claude-md-reference "CLAUDE.md refers to $p, which does not exist"
        done <<< "$(grep -oE '\.claude/skills/[A-Za-z0-9_./-]+' "$claude" 2>/dev/null | sed 's/[.]*$//' | sort -u || true)"
    fi
    if [ -f "$base" ]; then
        if git -C "$PROJECT" ls-files --error-unmatch -- .claude/orion/BASE_CLAUDE.md >/dev/null 2>&1 \
           && ! git -C "$PROJECT" diff --quiet HEAD -- .claude/orion/BASE_CLAUDE.md 2>/dev/null; then
            v_warn rules-copy-edited ".claude/orion/BASE_CLAUDE.md differs from the committed copy; orion overwrites it on update, so a rule change belongs in a pull request to orion, not here"
        else
            v_ok rules-copy ".claude/orion/BASE_CLAUDE.md is the shipped copy"
        fi
        # every skill and skill file the rules rely on must be installed
        n=0
        while IFS= read -r ref; do
            [ -n "$ref" ] || continue
            if [ ! -e "$PROJECT/$ref" ]; then
                v_fail rules-reference "the rules rely on $ref, which is not installed (a project skill without the orion marker kept its place, or it was deleted; fix: bash .claude/orion/orion.sh init --force)"
                n=$((n+1))
            fi
        done <<< "$( { grep -oE '\.claude/skills/[A-Za-z0-9_./-]+' "$base" | sed 's/[.]*$//'; grep -oE '`/[a-z][a-z0-9-]*' "$base" | sed 's|^`/|.claude/skills/|'; } 2>/dev/null | sort -u || true)"
        [ "$n" -eq 0 ] && v_ok rules-reference "every skill and skill file BASE_CLAUDE.md relies on is installed"
    fi

    # 3. skills: the orion-managed ones and the project's own
    if [ -d "$skills" ]; then
        shopt -s nullglob
        for entry in "$skills"/*/; do
            name=$(basename "$entry"); ours=0; [ -f "${entry%/}/$MARKER" ] && ours=1
            if [ ! -f "${entry%/}/SKILL.md" ]; then
                if [ "$ours" = "1" ]; then v_fail skill-file "$name (orion-managed) has no SKILL.md (fix: bash .claude/orion/orion.sh update --force)"
                else v_warn skill-file "$name (the project's own) has no SKILL.md, so Claude Code ignores it"; fi
                continue
            fi
            sname=$(skill_name "${entry%/}/SKILL.md")
            if [ -z "$sname" ]; then
                if [ "$ours" = "1" ]; then v_fail skill-name "$name (orion-managed) has no name: in its front matter (fix: bash .claude/orion/orion.sh update --force)"
                else v_warn skill-name "$name (the project's own) has no name: in its front matter"; fi
            elif [ "$sname" != "$name" ]; then
                if [ "$ours" = "1" ]; then v_fail skill-name "$name (orion-managed) declares name: $sname (fix: bash .claude/orion/orion.sh update --force)"
                else v_warn skill-name "$name (the project's own) declares name: $sname; folder and name should match"; fi
            fi
            [ -n "$sname" ] && { case " $names " in *" $sname "*) dups="$dups $sname" ;; esac; names="$names $sname"; }
            [ -d "$HOME/.claude/skills/$name" ] && v_warn skill-shadow "$name also exists at user level (~/.claude/skills/$name); two skills with one name are ambiguous - remove one"
            # a skill may ship its own post-install checks; the /orion-verify skill runs them
            if [ -f "${entry%/}/VERIFY.md" ]; then
                if [ -s "${entry%/}/VERIFY.md" ]; then checks="$checks $name"
                else v_warn skill-checks "$name ships an empty VERIFY.md (fill it or delete it)"; fi
            fi
        done
        shopt -u nullglob
        [ -n "$dups" ] && v_fail skill-duplicate "two skill folders declare the same name:$dups (fix: rename or remove one)"
        [ -z "$dups" ] && v_ok skills "every skill under .claude/skills has a SKILL.md whose name matches its folder"
        if [ -n "$checks" ]; then v_ok skill-checks "skills shipping their own VERIFY.md, run by /orion-verify:$checks"
        else v_ok skill-checks "no skill ships a VERIFY.md of its own"; fi
    else
        v_fail skills ".claude/skills is missing (fix: bash .claude/orion/orion.sh update --force)"
    fi

    # 4. settings: the session-start hook
    if [ ! -f "$settings" ]; then
        v_fail settings-hook ".claude/settings.json is missing, so the update check never runs (fix: bash .claude/orion/orion.sh update --force)"
    elif ! json_valid "$settings"; then
        v_fail settings-json ".claude/settings.json is not valid JSON; Claude Code ignores every setting in it (fix: repair it by hand, then re-run)"
    else
        n=$(grep -cF "$HOOK_NEEDLE" "$settings" || true)
        case "$n" in
            1) v_ok settings-hook ".claude/settings.json has the orion SessionStart hook once" ;;
            0) v_fail settings-hook ".claude/settings.json has no orion SessionStart hook (fix: bash .claude/orion/orion.sh update --force)" ;;
            *) v_warn settings-hook ".claude/settings.json has the orion SessionStart hook $n times (fix: delete the duplicates)" ;;
        esac
    fi

    # 5. git: what orion installed must reach the team
    if git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        n=""
        for p in CLAUDE.md .claude/orion/orion.sh .claude/skills .claude/settings.json; do
            [ -e "$PROJECT/$p" ] && git -C "$PROJECT" check-ignore -q -- "$p" 2>/dev/null && n="$n $p"
        done
        if [ -n "$n" ]; then v_warn git-ignored "ignored by .gitignore:$n - teammates will not get orion with a clone (fix: un-ignore them)"
        else v_ok git-tracked "nothing orion installed is ignored by git"; fi
    fi

    say "verify: $VERIFY_FAIL fail, $VERIFY_WARN warn"
    [ "$VERIFY_FAIL" -eq 0 ]
}

main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        init) cmd_init "$@" ;;
        update) cmd_update "$@" ;;
        check) cmd_check "$@" ;;
        verify) cmd_verify "$@" ;;
        status) cmd_status "$@" ;;
        uninstall) cmd_uninstall "$@" ;;
        help|-h|--help) usage ;;
        *) die "unknown command: $cmd (try: orion.sh help)" ;;
    esac
}

main "$@"
