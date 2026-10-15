#!/usr/bin/env bash
# Removes skill copies created by install.sh and the cron auto-pull entry.
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

MARKER=".orion-managed"

case "$TARGET" in
    claude) TARGET_DIR="$HOME/.claude/skills" ;;
    *) echo "Target '$TARGET' not supported."; exit 1 ;;
esac

# Remove every managed copy (any folder carrying our marker)
shopt -s nullglob
if [ -d "$TARGET_DIR" ]; then
    for entry in "$TARGET_DIR"/*/; do
        name=$(basename "$entry")
        if [ -f "${entry%/}/$MARKER" ]; then
            rm -rf "${entry%/}"
            echo "  -    $name"
        fi
    done
fi

# Status line: the baseline copy at ~/.claude/statusline is the user's (they may
# have edited it), so it is left in place; only the settings entry pointing at
# it is removed. A pre-baseline managed copy (statusline-orion) is removed.
LEGACY_DEST="$HOME/.claude/statusline-orion"
if [ -f "$LEGACY_DEST/$MARKER" ]; then
    rm -rf "$LEGACY_DEST"
    echo "  -    statusline-orion (old managed copy)"
fi
STATUS_DEST="$HOME/.claude/statusline"
if [ -f "$STATUS_DEST/.orion-baseline" ]; then
    echo "  =    statusline left in place (your copy of the baseline; delete $STATUS_DEST by hand if unwanted)"
fi
settings="$HOME/.claude/settings.json"
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
    if jq -e '.statusLine.command // "" | test("statusline-orion|/\\.claude/statusline/statusline\\.sh")' "$settings" >/dev/null 2>&1; then
        tmp=$(mktemp)
        jq 'del(.statusLine)' "$settings" > "$tmp" && mv "$tmp" "$settings"
        echo "statusLine setting removed from $settings"
    fi
fi

marker="# orion-skills-autopull"
if crontab -l 2>/dev/null | grep -q "$marker"; then
    crontab -l 2>/dev/null | grep -v "$marker" | crontab -
    echo "Cron entry removed"
fi

echo "Uninstall complete."
