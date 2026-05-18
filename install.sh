#!/usr/bin/env bash
# Installs the skills in this repo as user-level Claude Code skills via symlinks.
#
# Usage:
#   ./install.sh                       # interactive install
#   ./install.sh --target claude --schedule daily
#   ./install.sh --update              # called by cron; pull + link new skills
#   ./install.sh --help

set -euo pipefail

TARGET="claude"
SCHEDULE="none"
FORCE=0
UPDATE=0

usage() {
    sed -n '2,8p' "$0"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)   TARGET="$2"; shift 2 ;;
        --schedule) SCHEDULE="$2"; shift 2 ;;
        --force)    FORCE=1; shift ;;
        --update)   UPDATE=1; SCHEDULE="none"; shift ;;
        --help|-h)  usage ;;
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

shopt -s nullglob
added=0; skipped=0; existing=0; pruned=0

# Prune dangling symlinks pointing into our repo (skills removed upstream)
for entry in "$TARGET_DIR"/*; do
    [ -L "$entry" ] || continue
    target=$(readlink "$entry")
    case "$target" in
        "$SKILLS_SOURCE"/*)
            if [ ! -e "$target" ]; then
                rm "$entry"
                echo "  -    $(basename "$entry") (pruned dangling)"
                pruned=$((pruned+1))
            fi
            ;;
    esac
done
for skill in "$SKILLS_SOURCE"/*/; do
    [ -d "$skill" ] || continue
    name=$(basename "$skill")
    link="$TARGET_DIR/$name"
    skill_path="${skill%/}"

    if [ -L "$link" ]; then
        current="$(readlink "$link")"
        if [ "$current" = "$skill_path" ]; then
            echo "  ok   $name"
            existing=$((existing+1))
            continue
        fi
    fi

    if [ -e "$link" ] || [ -L "$link" ]; then
        if [ "$UPDATE" = "1" ]; then
            echo "  skip $name (exists, not our link)"
            skipped=$((skipped+1))
            continue
        fi
        if [ "$FORCE" != "1" ]; then
            read -r -p "  !  $name exists and is not our link. Overwrite? [y/N] " resp
            if [[ ! "$resp" =~ ^[Yy]$ ]]; then
                echo "  skip $name"
                skipped=$((skipped+1))
                continue
            fi
        fi
        rm -rf "$link"
    fi

    ln -s "$skill_path" "$link"
    echo "  +    $name"
    added=$((added+1))
done

echo ""
echo "[$added added, $existing already linked, $pruned pruned, $skipped skipped] -> $TARGET_DIR"

if [ "$UPDATE" = "1" ]; then exit 0; fi

if [ "$SCHEDULE" = "prompt" ]; then
    echo ""
    echo "Updates are manual by default — run './install.sh --update' (or ask Claude to)"
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
