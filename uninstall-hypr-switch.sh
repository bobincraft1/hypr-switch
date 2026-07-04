#!/usr/bin/env bash
#
# uninstall-hypr-switch.sh
# Removes hypr-switch and optionally its shell configs.
#
set -euo pipefail

HYPR_DIR="$HOME/.config/hypr"
SHELLS_DIR="$HYPR_DIR/shells"
BIN_DIR="$HOME/.local/bin"
SCRIPT_PATH="$BIN_DIR/hypr-switch"
CURRENT_FILE="$HYPR_DIR/.current_shell"

echo "== hypr-switch uninstaller =="
echo ""
echo "This will remove:"
echo "  - $SCRIPT_PATH"
echo "  - $CURRENT_FILE"
echo "  - the active hyprland.lua / hyprland.conf symlink in $HYPR_DIR"
echo ""
read -rp "Also delete all shell configs in $SHELLS_DIR ? [y/N]: " confirm

rm -f "$SCRIPT_PATH"
rm -f "$CURRENT_FILE"

# Only remove the top-level config if it's a symlink (never touch a real file)
for f in "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/hyprland.conf"; do
    if [[ -L "$f" ]]; then
        rm -f "$f"
        echo "Removed symlink: $f"
    fi
done

if [[ "$confirm" =~ ^[Yy]$ ]]; then
    rm -rf "$SHELLS_DIR"
    echo "Removed all shell configs in $SHELLS_DIR"
else
    echo "Kept shell configs in $SHELLS_DIR — delete manually if needed."
fi

echo ""
echo "== Uninstall complete =="
echo "Note: your active hyprland.lua/.conf symlink is gone."
echo "You'll need to point Hyprland at a config manually before your next login,"
echo "e.g.: ln -sf $SHELLS_DIR/<shell>/hyprland.lua $HYPR_DIR/hyprland.lua"
