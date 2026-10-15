#!/usr/bin/env bash
# orion - a repo-level utility framework for Claude Code projects.
#
# Everything orion ships is copied INTO the project (skills, a rules file, this
# script) and committed, so teammates get it with a plain git clone/pull. The
# only per-computer piece is the optional status line.
#
# Usage (run inside the project, or pass --project <dir>):
#   orion.sh init      [--source <git url|path>] [--ref <branch>] [--statusline|--no-statusline] [--force]
#   orion.sh update    [--force]        # fetch the latest orion and re-copy the files orion owns
#   orion.sh check     [--force]        # session-start hook: is a newer orion available? (once a day)
#   orion.sh status                     # what is installed, which version, which update mode
#   orion.sh uninstall [--yes]          # remove everything orion owns, keep everything yours
#   orion.sh help
#
# First-time bootstrap, no clone needed (run inside the project):
#   curl -fsSL https://raw.githubusercontent.com/nachogl1/orion/main/orion.sh | bash -s -- init
#
# What orion owns in a project (overwritten on update, removed on uninstall):
#   .claude/skills/<skill>/           every folder carrying a `.orion-managed` marker
#   .claude/orion/orion.sh            this script
#   .claude/orion/ORION.md            the orion rules, imported by CLAUDE.md
#   .claude/orion/VERSION             commit the files came from
#   .claude/orion/.orion-manifest     the list above
# What orion creates ONCE and never touches again (yours):
#   CLAUDE.md                         created from the template if missing; otherwise only the
#                                     import line `@.claude/orion/ORION.md` is added
#   .claude/orion/config.json         updateMode: ask | auto | off, plus source/ref
#   .claude/settings.json             one SessionStart hook entry is added (removed on uninstall)

set -euo pipefail

ORION_DEFAULT_SOURCE="https://github.com/nachogl1/orion.git"
ORION_DEFAULT_REF="main"
MARKER=".orion-managed"
IMPORT_LINE="@.claude/orion/ORION.md"
HOOK_NEEDLE="/.claude/orion/orion.sh"
HOOK_CMD='bash "${CLAUDE_PROJECT_DIR}/.claude/orion/orion.sh" check'
CHECK_INTERVAL_SECONDS=86400

# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
warn() { printf 'orion: %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

usage() { sed -n '2,30p' "$0" 2>/dev/null || true; exit 0; }

is_tty() { [ -t 0 ] && [ -t 1 ]; }

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

# Read a flat string value from config.json without jq.
config_get() {  # file key default
    local v=""
    if [ -f "$1" ]; then
        v=$(sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -n1)
    fi
    printf '%s' "${v:-$3}"
}

version_sha() { sed -n '1p' "$1" 2>/dev/null || true; }

short() { printf '%s' "${1:0:7}"; }

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
                read -r -p "  !  $name exists and is not an orion copy. Overwrite? [y/N] " resp
                if [[ ! "$resp" =~ ^[Yy]$ ]]; then say "  skip $name"; skipped=$((skipped+1)); continue; fi
            fi
        fi
        copy_managed "${skill%/}" "$dest"
        if [ "$is_ours" = "1" ]; then say "  ~    $name"; updated=$((updated+1)); else say "  +    $name"; added=$((added+1)); fi
    done
    shopt -u nullglob
    say "  skills: $added added, $updated updated, $pruned removed, $skipped skipped"
}

apply_core() {  # source ref
    local dir="$PROJECT/.claude/orion" tmp
    mkdir -p "$dir"
    # orion.sh may be the script currently running: write beside, then mv (atomic).
    tmp="$dir/.orion.sh.new"; cp "$SRC_DIR/orion.sh" "$tmp"; chmod +x "$tmp"; mv -f "$tmp" "$dir/orion.sh"
    cp "$SRC_DIR/baselines/ORION.md" "$dir/ORION.md"
    printf '%s\n%s\n%s\n' "$SRC_SHA" "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$dir/VERSION"
    printf '%s\n' "orion.sh" "ORION.md" "VERSION" ".orion-manifest" > "$dir/.orion-manifest"
    if [ ! -f "$dir/config.json" ]; then
        printf '{\n  "updateMode": "ask",\n  "source": "%s",\n  "ref": "%s"\n}\n' "$1" "$2" > "$dir/config.json"
        say "  +    .claude/orion/config.json (yours: updateMode ask | auto | off)"
    fi
    say "  ~    .claude/orion/{orion.sh, ORION.md, VERSION} @ $(short "$SRC_SHA")"
}

apply_claude_md() {
    local f="$PROJECT/CLAUDE.md" tmp
    if [ ! -f "$f" ]; then
        cp "$SRC_DIR/baselines/BASE_CLAUDE.md" "$f"
        say "  +    CLAUDE.md (from the orion template - fill in the <angle-bracket> slots; it is yours now)"
    elif ! grep -qxF "$IMPORT_LINE" "$f"; then
        tmp=$(mktemp); { printf '%s\n\n' "$IMPORT_LINE"; cat "$f"; } > "$tmp"; mv "$tmp" "$f"
        say "  ~    CLAUDE.md (import line added at the top; nothing else touched)"
    else
        say "  =    CLAUDE.md (already imports the orion rules)"
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
    local source="$ORION_DEFAULT_SOURCE" ref="$ORION_DEFAULT_REF" force=0 statusline="prompt" project="" resp
    while [ $# -gt 0 ]; do
        case "$1" in
            --source) source="$2"; shift 2 ;;
            --ref) ref="$2"; shift 2 ;;
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
    say "orion init -> $PROJECT"
    fetch_source "$source" "$ref"
    retire_user_level_copies
    apply_skills init "$force"
    apply_core "$source" "$ref"
    apply_claude_md
    settings_add_hook "$PROJECT/.claude/settings.json"
    if [ "$statusline" = "prompt" ]; then
        statusline=no
        if is_tty; then
            read -r -p "Also install the orion status line for this computer (~/.claude/statusline, optional)? [y/N] " resp
            [[ "$resp" =~ ^[Yy]$ ]] && statusline=yes
        fi
    fi
    [ "$statusline" = "yes" ] && install_statusline "$force"
    say ""
    say "done. Review with 'git status', then commit the new files on a branch so your team gets them."
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
        say "If .claude/orion/ORION.md changed, re-read CLAUDE.md for rules that now contradict it and fix them in the same commit."
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
    local dir="$PROJECT/.claude/orion" cfg="$PROJECT/.claude/orion/config.json" mode source ref current latest stamp now last ctx
    [ -f "$dir/VERSION" ] || exit 0
    mode="$(config_get "$cfg" updateMode ask)"
    [ "$mode" = "off" ] && exit 0
    stamp="${XDG_CACHE_HOME:-$HOME/.cache}/orion/$(printf '%s' "$PROJECT" | cksum | cut -d' ' -f1).last-check"
    now=$(date +%s)
    if [ "$force" != "1" ] && [ -f "$stamp" ]; then
        last=$(cat "$stamp" 2>/dev/null || echo 0)
        [ $((now - last)) -lt "$CHECK_INTERVAL_SECONDS" ] && exit 0
    fi
    mkdir -p "$(dirname "$stamp")" 2>/dev/null && printf '%s' "$now" > "$stamp" || true
    source="$(config_get "$cfg" source "$ORION_DEFAULT_SOURCE")"; ref="$(config_get "$cfg" ref "$ORION_DEFAULT_REF")"
    current="$(version_sha "$dir/VERSION")"
    latest="$(latest_sha "$source" "$ref")"
    [ -n "$latest" ] || exit 0
    [ "$latest" = "$current" ] && exit 0
    case "$mode" in
        auto)
            if cmd_update --project "$PROJECT" --quiet >/dev/null 2>&1; then
                ctx="orion (the repo-level utility framework in .claude/orion) was updated automatically from $(short "$current") to $(short "$latest"), as the project's updateMode is 'auto'. Tell the user in one line, and remind them to review 'git status' and commit the changed orion files on a branch."
            else
                ctx="orion tried to update itself automatically ($(short "$current") -> $(short "$latest")) and failed. Tell the user in one line that running 'bash .claude/orion/orion.sh update' by hand will show the error."
            fi ;;
        *)
            ctx="A newer orion is available for this project ($(short "$current") -> $(short "$latest")). Before anything else, ask the user with the AskUserQuestion tool whether to update orion now (options: 'Update now' recommended, 'Not now'). If they say yes, run 'bash .claude/orion/orion.sh update' from the project root, summarise the changed files in one line, and remind them to commit on a branch. If they say no, continue with their request and do not mention it again this session." ;;
    esac
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ctx"
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
    shopt -s nullglob
    for entry in "$PROJECT"/.claude/skills/*/; do
        [ -f "${entry%/}/$MARKER" ] && { say "skill:      $(basename "$entry")"; n=$((n+1)); }
    done
    shopt -u nullglob
    say "skills:     $n orion-managed"
    grep -qxF "$IMPORT_LINE" "$PROJECT/CLAUDE.md" 2>/dev/null && say "CLAUDE.md:  imports the orion rules" || say "CLAUDE.md:  does NOT import the orion rules (run: orion.sh update)"
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
        read -r -p "Remove everything orion owns from $PROJECT (your CLAUDE.md rules and your own skills stay)? [y/N] " resp
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
    if [ -f "$f" ] && grep -qxF "$IMPORT_LINE" "$f"; then
        tmp=$(mktemp); grep -vxF "$IMPORT_LINE" "$f" | sed '1{/^$/d;}' > "$tmp"; mv "$tmp" "$f"
        say "  ~    CLAUDE.md (import line removed; your rules untouched)"
    fi
    settings_remove_hook "$PROJECT/.claude/settings.json"
    say "done. The status line (if installed) is a per-computer copy under ~/.claude/statusline and was left alone."
}

main() {
    local cmd="${1:-help}"; shift || true
    case "$cmd" in
        init) cmd_init "$@" ;;
        update) cmd_update "$@" ;;
        check) cmd_check "$@" ;;
        status) cmd_status "$@" ;;
        uninstall) cmd_uninstall "$@" ;;
        help|-h|--help) usage ;;
        *) die "unknown command: $cmd (try: orion.sh help)" ;;
    esac
}

main "$@"
