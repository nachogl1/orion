#!/usr/bin/env bash
# Installs the skills in this repo as user-level Claude Code skills via file copies.
# Copies are used instead of symlinks: every update re-copies the skill content.
#
# Usage:
#   ./install.sh                       # interactive install
#   ./install.sh --target claude --schedule daily
#   ./install.sh --statusline          # also configure the orion status line
#   ./install.sh --update              # called by cron; pull + link new skills
#   ./install.sh --help

set -euo pipefail

TARGET="claude"
SCHEDULE="none"
FORCE=0
UPDATE=0
STATUSLINE=0

usage() {
    sed -n '2,9p' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)     TARGET="$2"; shift 2 ;;
        --schedule)   SCHEDULE="$2"; shift 2 ;;
        --force)      FORCE=1; shift ;;
        --statusline) STATUSLINE=1; shift ;;
        --update)     UPDATE=1; SCHEDULE="none"; shift ;;
        --help|-h)    usage ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SKILLS_SOURCE="$REPO_ROOT/skills"

case "$TARGET" in
    claude) TARGET_DIR="$HOME/.claude/skills" ;;
    *) echo "Target '$TARGET' not yet supported."; exit 1 ;;
esac

if [ "$UPDATE" = "1" ]; then
    echo "[update] git pull --ff-only in $REPO_ROOT"
    git -C "$REPO_ROOT" pull --ff-only
fi

mkdir -p "$TARGET_DIR"

# Marker file dropped into every copied folder so later runs recognise their
# own copies (copies are otherwise indistinguishable from a user's own skills).
MARKER=".orion-managed"

copy_managed() {  # src dst
    rm -rf "$2"
    cp -R "$1" "$2"
    printf '%s' "$1" > "$2/$MARKER"
}

shopt -s nullglob
added=0; skipped=0; updated=0; pruned=0

# Prune managed copies whose source skill no longer exists (removed/renamed upstream)
for entry in "$TARGET_DIR"/*/; do
    name=$(basename "$entry")
    [ -f "${entry%/}/$MARKER" ] || continue
    if [ ! -d "$SKILLS_SOURCE/$name" ]; then
        rm -rf "${entry%/}"
        echo "  -    $name (pruned removed skill)"
        pruned=$((pruned+1))
    fi
done

for skill in "$SKILLS_SOURCE"/*/; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    dest="$TARGET_DIR/$name"
    skill_path="${skill%/}"

    is_ours=0
    [ -f "$dest/$MARKER" ] && is_ours=1

    if [ -e "$dest" ] && [ "$is_ours" != "1" ]; then
        if [ "$UPDATE" = "1" ]; then
            echo "  skip $name (exists, not ours)"
            skipped=$((skipped+1))
            continue
        fi
        if [ "$FORCE" != "1" ]; then
            read -r -p "  !  $name exists and is not an orion copy. Overwrite? [y/N] " resp
            if [[ ! "$resp" =~ ^[Yy]$ ]]; then
                echo "  skip $name"
                skipped=$((skipped+1))
                continue
            fi
        fi
    fi

    copy_managed "$skill_path" "$dest"
    if [ "$is_ours" = "1" ]; then
        echo "  ~    $name (updated)"
        updated=$((updated+1))
    else
        echo "  +    $name"
        added=$((added+1))
    fi
done

echo ""
echo "[$added added, $updated updated, $pruned pruned, $skipped skipped] -> $TARGET_DIR"

# ---------------------------------------------------------------------------
# Status line - copy ./statusline to ~/.claude/statusline-orion (same copy +
# marker pattern as skills, so --update re-copies it), then optionally point the
# statusLine setting in ~/.claude/settings.json at it (opt-in; never in --update).
# ---------------------------------------------------------------------------
STATUS_SOURCE="$REPO_ROOT/statusline"
STATUS_LINK="$HOME/.claude/statusline-orion"

if [ -d "$STATUS_SOURCE" ]; then
    link_ok=0
    status_is_ours=0
    [ -f "$STATUS_LINK/$MARKER" ] && status_is_ours=1
    if [ -e "$STATUS_LINK" ] && [ "$status_is_ours" != "1" ]; then
        if [ "$UPDATE" = "1" ]; then
            echo "  skip statusline-orion (exists, not ours)"
        else
            do_replace="$FORCE"
            if [ "$do_replace" != "1" ]; then
                read -r -p "  !  statusline-orion exists and is not an orion copy. Overwrite? [y/N] " resp
                [[ "$resp" =~ ^[Yy]$ ]] && do_replace=1
            fi
            if [ "$do_replace" = "1" ]; then
                copy_managed "$STATUS_SOURCE" "$STATUS_LINK"
                echo "  +    statusline-orion"
                link_ok=1
            else
                echo "  skip statusline-orion"
            fi
        fi
    else
        copy_managed "$STATUS_SOURCE" "$STATUS_LINK"
        if [ "$status_is_ours" = "1" ]; then
            echo "  ~    statusline-orion (updated)"
        else
            echo "  +    statusline-orion"
        fi
        link_ok=1
    fi

    if [ "$link_ok" = "1" ] && [ "$UPDATE" != "1" ]; then
        configure="$STATUSLINE"
        if [ "$configure" != "1" ] && [ "$FORCE" != "1" ]; then
            read -r -p "Configure the orion status line in ~/.claude/settings.json? [y/N] " resp
            [[ "$resp" =~ ^[Yy]$ ]] && configure=1
        fi
        if [ "$configure" = "1" ]; then
            settings="$HOME/.claude/settings.json"
            sl_cmd="bash \"$STATUS_LINK/statusline.sh\""
            mkdir -p "$HOME/.claude"
            if [ -f "$settings" ]; then
                tmp=$(mktemp)
                jq --arg cmd "$sl_cmd" '.statusLine = {type: "command", command: $cmd}' "$settings" > "$tmp" && mv "$tmp" "$settings"
            else
                jq -n --arg cmd "$sl_cmd" '{statusLine: {type: "command", command: $cmd}}' > "$settings"
            fi
            echo "statusLine configured in $settings"

            # Pre-warm the 30-day cost cache so the status line shows the real
            # figure on first render instead of the "$..." placeholder. Without
            # this the in-script background refresh leaves it pending until the
            # first npx ccusage run finishes. Best-effort: needs node/npx.
            echo "Warming the 30-day cost cache (one-time, needs node/npx)..."
            ( since=$(date -d "30 days ago" +%Y%m%d 2>/dev/null || date -v-30d +%Y%m%d 2>/dev/null)
              cache="$HOME/.cache/claude-statusline/cost-30d.txt"
              mkdir -p "$(dirname "$cache")" 2>/dev/null
              total=$(npx -y ccusage daily --json --since "$since" 2>/dev/null | jq -r '.totals.totalCost // empty')
              [ -n "$total" ] && printf '%.2f' "$total" > "$cache" && echo "  cost cache: $total" ) || true
        fi
    fi
fi

if [ "$UPDATE" = "1" ]; then exit 0; fi

if [ "$SCHEDULE" = "prompt" ]; then
    echo ""
    echo "Updates are manual by default - run './install.sh --update' (or ask Claude to)"
    echo "when you want to pull the latest skills."
    read -r -p "Register a scheduled auto-pull anyway? (daily/hourly/none) [none] " resp
    SCHEDULE="${resp:-none}"
fi

case "$SCHEDULE" in
    none) exit 0 ;;
    daily)  cron_expr="0 9 * * *" ;;
    hourly) cron_expr="0 * * * *" ;;
    *) echo "Unknown schedule '$SCHEDULE', skipping."; exit 0 ;;
esac

marker="# orion-skills-autopull"
cron_line="$cron_expr '$REPO_ROOT/install.sh' --update >> '$REPO_ROOT/.update.log' 2>&1 $marker"
( crontab -l 2>/dev/null | grep -v "$marker" ; echo "$cron_line" ) | crontab -
echo "Cron entry registered ($SCHEDULE)"
