#!/usr/bin/env bash
# Removes skill symlinks and the cron auto-pull entry.
#
# Usage: ./uninstall.sh [--target claude]

set -euo pipefail

TARGET="claude"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --help|-h) sed -n '2,5p' "$0"; exit 0 ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SKILLS_SOURCE="$REPO_ROOT/skills"

case "$TARGET" in
    claude) TARGET_DIR="$HOME/.claude/skills" ;;
    *) echo "Target '$TARGET' not supported."; exit 1 ;;
esac

if [ -d "$SKILLS_SOURCE" ]; then
    for skill in "$SKILLS_SOURCE"/*/; do
        [ -d "$skill" ] || continue
        name=$(basename "$skill")
        link="$TARGET_DIR/$name"
        if [ -L "$link" ] && [ "$(readlink "$link")" = "${skill%/}" ]; then
            rm "$link"
            echo "  -    $name"
        elif [ -e "$link" ]; then
            echo "  skip $name (not our link)"
        fi
    done
fi

marker="# orion-skills-autopull"
if crontab -l 2>/dev/null | grep -q "$marker"; then
    crontab -l 2>/dev/null | grep -v "$marker" | crontab -
    echo "Cron entry removed"
fi

echo "Uninstall complete."
