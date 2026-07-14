#!/usr/bin/env bash
#
# uninstall-hypr-switch.sh
# Removes hypr-switch v2 cleanly. Unlike v1 (which only ever managed a single
# hyprland.lua/.conf symlink), v2 may have symlinked many app folders across
# ~/.config and several dotfiles in $HOME. This uninstaller de-symlinks every
# currently-active item back into a REAL file/directory first — restoring
# whatever content is currently live — so nothing is left broken afterward,
# then optionally removes ~/.hypr-switch (all stored shells) entirely.
#
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "This uninstaller requires bash, but bash was not found on PATH." >&2
        exit 1
    fi
fi

set -uo pipefail
shopt -s dotglob

STORAGE_ROOT="$HOME/.hypr-switch"
BIN_PATH="$HOME/.local/bin/hypr-switch"
CONFIG_DIR="$HOME/.config"

# Must match hypr-switch's own WATCHED_HOME_ITEMS exactly, so every dotfile
# it could possibly have symlinked is correctly found and restored here too.
WATCHED_HOME_ITEMS=(
    ".zshrc" ".bashrc" ".zshenv" ".bash_profile" ".themes" ".icons"
)

echo "== hypr-switch uninstaller =="
echo ""

if [[ ! -d "$STORAGE_ROOT" ]]; then
    echo "No hypr-switch storage found at $STORAGE_ROOT — nothing to restore."
else
    echo "Restoring every currently-symlinked item to a real file/directory"
    echo "(preserving whatever content is currently active) before removing anything..."
    echo ""

    restored=0

    if [[ -d "$CONFIG_DIR" ]]; then
        for entry in "$CONFIG_DIR"/*; do
            [[ -e "$entry" ]] || continue
            [[ -L "$entry" ]] || continue
            resolved="$(readlink -f "$entry")"
            case "$resolved" in
                "$STORAGE_ROOT"/*)
                    if [[ -e "$resolved" ]]; then
                        rm -f "$entry"
                        if cp -a "$resolved" "$entry"; then
                            echo "  restored: config/$(basename "$entry")"
                            restored=$((restored + 1))
                        else
                            echo "  ERROR: failed to restore $entry" >&2
                        fi
                    else
                        echo "  WARNING: $entry is a broken symlink -> $resolved. Leaving as a dangling symlink; investigate manually." >&2
                    fi
                    ;;
            esac
        done
    fi

    for item in "${WATCHED_HOME_ITEMS[@]}"; do
        real="$HOME/$item"
        [[ -e "$real" ]] || continue
        [[ -L "$real" ]] || continue
        resolved="$(readlink -f "$real")"
        case "$resolved" in
            "$STORAGE_ROOT"/*)
                if [[ -e "$resolved" ]]; then
                    rm -f "$real"
                    if cp -a "$resolved" "$real"; then
                        echo "  restored: home/$item"
                        restored=$((restored + 1))
                    else
                        echo "  ERROR: failed to restore $real" >&2
                    fi
                else
                    echo "  WARNING: $real is a broken symlink -> $resolved. Leaving as a dangling symlink; investigate manually." >&2
                fi
                ;;
        esac
    done

    echo ""
    echo "Restored $restored item(s) to real files/directories."
fi

rm -f "$BIN_PATH"
echo "Removed: $BIN_PATH"

echo ""
if [[ -d "$STORAGE_ROOT" ]]; then
    read -rp "Also delete all stored shells (everything under $STORAGE_ROOT, including 'default')? [y/N]: " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$STORAGE_ROOT"
        echo "Removed: $STORAGE_ROOT"
    else
        echo "Kept: $STORAGE_ROOT (your other captured shells are still there if you reinstall later)"
    fi
fi

echo ""
echo "== Uninstall complete =="
echo "Your currently-active configuration is now made of ordinary real files"
echo "again — nothing under ~/.config or your dotfiles depends on hypr-switch"
echo "anymore, whether or not you chose to keep $STORAGE_ROOT."
