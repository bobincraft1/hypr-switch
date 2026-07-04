#!/usr/bin/env bash
#
# install-hypr-switch.sh
# Installer for hypr-switch — a symlink-based shell switcher for Hyprland.
# https://github.com/bobincraft1/hypr-switch
#
# hypr-switch itself auto-discovers shells from ~/.config/hypr/shells/ every
# time it runs, so this installer's only jobs are:
#   1. Install the hypr-switch command (and VERIFY it actually landed, is
#      executable, and is runnable — not just assume the copy worked)
#   2. Ensure ~/.local/bin is actually on PATH for your shell, and verify
#      that too, rather than silently hoping it already is
#   3. Optionally generate skeleton configs for any shell names you pass in
#      that don't already have one
#
# Once installed, adding a new shell NEVER requires re-running this script —
# just `mkdir -p ~/.config/hypr/shells/<name>` and drop a hyprland.lua or
# hyprland.conf inside. hypr-switch will pick it up on the very next run.
#

# --- Bash self-guard --------------------------------------------------------
# Same class of bug as hypr-switch itself: if this installer is ever invoked
# via a POSIX shell instead of bash, "set -euo pipefail" and other bash-only
# syntax below would fail immediately, sometimes silently. Re-exec under a
# real bash before anything else runs, no matter how this script was called.
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    else
        echo "This installer requires bash, but bash was not found on PATH." >&2
        exit 1
    fi
fi
# -----------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELLS_DIR="$HOME/.config/hypr/shells"
HYPR_DIR="$HOME/.config/hypr"
BIN_DIR="$HOME/.local/bin"
SCRIPT_PATH="$BIN_DIR/hypr-switch"
LOCK_CMD='~/.local/share/quickshell-lockscreen/lock.sh'
TERMINAL_CMD='kitty'

echo "== hypr-switch installer =="

mkdir -p "$SHELLS_DIR" "$BIN_DIR"

# --- 1. Install the standalone hypr-switch script — copy, chmod, and VERIFY each step ---
if [[ ! -f "$SCRIPT_DIR/hypr-switch" ]]; then
    echo "ERROR: hypr-switch script not found next to this installer (expected: $SCRIPT_DIR/hypr-switch)" >&2
    exit 1
fi

# Copy, then immediately verify the copy actually landed and matches the source.
# A silent cp failure (permissions, disk full, weird filesystem) would otherwise
# let the script print a false "success" message and move on.
cp "$SCRIPT_DIR/hypr-switch" "$SCRIPT_PATH"
if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "ERROR: copy to $SCRIPT_PATH did not produce a file. Check permissions on $BIN_DIR." >&2
    exit 1
fi
if ! cmp -s "$SCRIPT_DIR/hypr-switch" "$SCRIPT_PATH"; then
    echo "ERROR: copied file at $SCRIPT_PATH does not match the source. Copy may have been truncated or corrupted." >&2
    exit 1
fi

# chmod, then verify the executable bit is actually set — don't just trust the exit code.
chmod +x "$SCRIPT_PATH"
if [[ ! -x "$SCRIPT_PATH" ]]; then
    echo "ERROR: $SCRIPT_PATH exists but is still not executable after chmod +x." >&2
    echo "This can happen on filesystems mounted 'noexec' (some /tmp, network shares, some Termux setups)." >&2
    echo "Try moving hypr-switch to a normal writable location under \$HOME, e.g.:" >&2
    echo "  mkdir -p \$HOME/.local/bin && cp \"$SCRIPT_DIR/hypr-switch\" \$HOME/.local/bin/ && chmod +x \$HOME/.local/bin/hypr-switch" >&2
    exit 1
fi

# Final proof, not just a permissions check: actually RUN it and confirm it responds.
# This catches cases chmod/cmp can't: wrong interpreter, missing bash on PATH inside
# the script's own shebang resolution, line-ending corruption (CRLF from Windows-edited
# files), etc. If this fails, nothing downstream should claim success.
if ! "$SCRIPT_PATH" --help >/dev/null 2>&1; then
    echo "ERROR: $SCRIPT_PATH was copied and made executable, but running it failed." >&2
    echo "Common causes: Windows line endings (CRLF) in the file, or bash not installed." >&2
    echo "Try:  sed -i 's/\r$//' \"$SCRIPT_PATH\"   (fixes CRLF line endings)" >&2
    echo "Then re-run this installer." >&2
    exit 1
fi

echo "[1/6] Installed hypr-switch to $SCRIPT_PATH — copy verified, executable bit verified, execution verified."

# ---------------------------------------------------------------------------
# Back up an existing real config as the "default" shell.
#
# If ~/.config/hypr/hyprland.lua or hyprland.conf already exists as a REAL
# file (not a symlink hypr-switch itself created earlier), it means the
# person has a working Hyprland setup predating hypr-switch. Rather than
# leave it sitting there untouched and invisible to `hypr-switch --list`,
# move it into shells/default/ and put a symlink back in its place — so the
# active config keeps working immediately, AND it's now a normal, switchable
# shell called "default" with zero extra registration required (discovery is
# purely filesystem-based, so this is picked up automatically).
#
# Symlinks are explicitly excluded from this check (-f on a symlink target
# still returns true, so we check ! -L first) — re-running this installer
# must never re-"back up" a symlink hypr-switch already manages.
# ---------------------------------------------------------------------------
echo ""
echo "[2/6] Checking for an existing config to preserve as 'default'..."

DEFAULT_DIR="$SHELLS_DIR/default"
BACKED_UP=false

for existing in "$HYPR_DIR/hyprland.lua" "$HYPR_DIR/hyprland.conf"; do
    filename="$(basename "$existing")"

    # Only act on a REAL file — never a symlink (already-managed by hypr-switch)
    # and never something that doesn't exist at all.
    if [[ -f "$existing" && ! -L "$existing" ]]; then
        if [[ -e "$DEFAULT_DIR/$filename" ]]; then
            echo "  shells/default/$filename already exists — leaving $existing untouched to avoid overwriting it."
            continue
        fi

        mkdir -p "$DEFAULT_DIR"
        mv "$existing" "$DEFAULT_DIR/$filename"

        # Verify the move actually happened before touching anything else.
        if [[ ! -f "$DEFAULT_DIR/$filename" ]]; then
            echo "  ERROR: failed to move $existing to $DEFAULT_DIR/$filename — aborting backup for this file." >&2
            continue
        fi
        if [[ -e "$existing" ]]; then
            echo "  ERROR: $existing still exists after move — refusing to symlink over it. Check permissions." >&2
            continue
        fi

        ln -sf "$DEFAULT_DIR/$filename" "$existing"

        # Verify the replacement symlink actually points where expected.
        if [[ "$(readlink -f "$existing")" == "$(readlink -f "$DEFAULT_DIR/$filename")" ]]; then
            echo "  Backed up existing $filename to $DEFAULT_DIR/$filename"
            echo "  Replaced $existing with a symlink pointing at it — your current setup keeps working."
            BACKED_UP=true
        else
            echo "  ERROR: symlink verification failed for $existing — check it manually." >&2
        fi
    fi
done

if [[ "$BACKED_UP" == true ]]; then
    echo "$SHELLS_DIR/default" > /dev/null  # no-op, DEFAULT_DIR already correct
    echo "default" > "$HYPR_DIR/.current_shell"
    echo "  'default' is now a normal shell — confirm with: hypr-switch --list"
else
    echo "  No existing real config found to back up (already using hypr-switch, or fresh install)."
fi

# ---------------------------------------------------------------------------
# PATH setup — the #1 real-world cause of "command not found" after install.
# A correctly installed, executable script is still "not found" if the shell
# looking for it doesn't have $BIN_DIR on PATH. This function:
#   1. Checks whether $BIN_DIR is already on PATH (nothing to do if so)
#   2. If not, patches the correct config file for whichever shell(s) are
#      actually present on the system — fish, bash, AND zsh, not just one
#   3. Verifies afterward that `hypr-switch` actually resolves by name —
#      not just that a line was appended to a config file
# Defined as a function and called unconditionally further down, so it always
# runs regardless of whether shell names were passed to this installer.
# ---------------------------------------------------------------------------
setup_and_verify_path() {
    echo ""
    echo "[5/6] Checking PATH..."

    local path_already_ok=false
    case ":$PATH:" in
        *":$BIN_DIR:"*) path_already_ok=true ;;
    esac

    if [[ "$path_already_ok" == true ]]; then
        echo "  $BIN_DIR is already on PATH for this session."
    else
        echo "  $BIN_DIR is not on PATH yet — patching shell config file(s)."

        local patched_any=false

        # fish
        if command -v fish >/dev/null 2>&1; then
            if fish -c "fish_add_path $BIN_DIR" 2>/dev/null; then
                echo "  [fish] Added $BIN_DIR via fish_add_path (persists automatically)."
                patched_any=true
            else
                echo "  [fish] fish_add_path failed — add manually: fish_add_path $BIN_DIR" >&2
            fi
        fi

        # bash
        if command -v bash >/dev/null 2>&1; then
            local bashrc="$HOME/.bashrc"
            touch "$bashrc"
            if ! grep -qF "$BIN_DIR" "$bashrc" 2>/dev/null; then
                {
                    echo ""
                    echo "# Added by hypr-switch installer"
                    echo "export PATH=\"$BIN_DIR:\$PATH\""
                } >> "$bashrc"
                echo "  [bash] Added PATH export to $bashrc"
                patched_any=true
            else
                echo "  [bash] $bashrc already references $BIN_DIR — left untouched."
            fi
        fi

        # zsh
        if command -v zsh >/dev/null 2>&1; then
            local zshrc="$HOME/.zshrc"
            touch "$zshrc"
            if ! grep -qF "$BIN_DIR" "$zshrc" 2>/dev/null; then
                {
                    echo ""
                    echo "# Added by hypr-switch installer"
                    echo "export PATH=\"$BIN_DIR:\$PATH\""
                } >> "$zshrc"
                echo "  [zsh] Added PATH export to $zshrc"
                patched_any=true
            else
                echo "  [zsh] $zshrc already references $BIN_DIR — left untouched."
            fi
        fi

        if [[ "$patched_any" == false ]]; then
            echo "  WARNING: could not detect fish, bash, or zsh config to patch automatically." >&2
            echo "  Add this line to your shell's config file manually:" >&2
            echo "    export PATH=\"$BIN_DIR:\$PATH\"" >&2
        fi
    fi

    # Export for the rest of THIS script run, so the verification check below
    # (and anything after it in this same invocation) can find hypr-switch
    # even before a new terminal session picks up the patched config file.
    export PATH="$BIN_DIR:$PATH"

    # Real verification: actually resolve the command by name, the same way
    # a user's shell would, rather than just checking the file exists on disk.
    if command -v hypr-switch >/dev/null 2>&1; then
        echo "  Verified: 'hypr-switch' resolves on PATH."
    else
        echo "  ERROR: 'hypr-switch' still does not resolve on PATH even after patching." >&2
        echo "  This should not happen — please open an issue with your shell and OS details." >&2
    fi
}

# --- 2. Detect uwsm, purely to choose the right skeleton exit keybind text ---
if command -v uwsm >/dev/null 2>&1 && pgrep -x uwsm >/dev/null 2>&1; then
    EXIT_LUA_LINE='hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd("uwsm stop"), { description = "Logout" })'
    EXIT_CONF_LINE='bind = SUPER SHIFT, E, exec, uwsm stop'
else
    EXIT_LUA_LINE='hl.bind("SUPER + SHIFT + E", hl.dsp.exit(), { description = "Logout" })'
    EXIT_CONF_LINE='bind = SUPER SHIFT, E, exit,'
fi
echo "[3/6] Detected session type, skeleton exit keybind chosen."

# --- 4. Optionally generate skeleton configs for any shell names passed in ---
if [[ $# -eq 0 ]]; then
    echo "[4/6] No shell names passed — skipping skeleton generation."

    setup_and_verify_path

    echo ""
    echo "[6/6] Done."
    echo ""
    echo "== Install complete =="
    echo "hypr-switch is installed and will auto-discover any shells already"
    echo "present in $SHELLS_DIR"
    if [[ "$BACKED_UP" == true ]]; then
        echo ""
        echo "Your pre-existing config was preserved as the 'default' shell."
        echo "Confirm with: hypr-switch --list"
    fi
    echo ""
    echo "To add a shell right now:"
    echo "  mkdir -p $SHELLS_DIR/<name>"
    echo "  cp /path/to/your/hyprland.lua $SHELLS_DIR/<name>/hyprland.lua"
    echo ""
    echo "Then activate it with:"
    echo "  hypr-switch <name>"
    exit 0
fi

SHELL_NAMES=("$@")
echo "[4/6] Processing shell names: ${SHELL_NAMES[*]}"

for shell in "${SHELL_NAMES[@]}"; do
    dir="$SHELLS_DIR/$shell"
    mkdir -p "$dir"

    lua_file="$dir/hyprland.lua"
    conf_file="$dir/hyprland.conf"

    if [[ -f "$lua_file" ]]; then
        filetype="hyprland.lua"
        echo "  [$shell] Existing hyprland.lua found — will inject keybinds if missing."
    elif [[ -f "$conf_file" ]]; then
        filetype="hyprland.conf"
        echo "  [$shell] Existing hyprland.conf found — will inject keybinds if missing."
    else
        echo ""
        echo "  No config found for '$shell'."
        read -rp "    Generate a new one as .lua or .conf? [lua/conf]: " answer
        case "$answer" in
            conf) filetype="hyprland.conf" ;;
            *)    filetype="hyprland.lua" ;;
        esac
    fi

    target="$dir/$filetype"

    if [[ ! -f "$target" ]]; then
        if [[ "$filetype" == "hyprland.lua" ]]; then
            cat > "$target" << SKEL
-- Minimal hyprland.lua skeleton for shell: $shell
-- Generated by install-hypr-switch.sh

monitor = { }

-- Keybinds
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("hypr-switch"), { description = "Switch Hyprland shell" })
hl.bind("SUPER + T", hl.dsp.exec_cmd("$TERMINAL_CMD"), { description = "Open terminal" })
hl.bind("SUPER + L", hl.dsp.exec_cmd("$LOCK_CMD"), { description = "Lock screen" })
$EXIT_LUA_LINE

-- Add your window rules, animations, and layout config below
SKEL
        else
            cat > "$target" << SKEL
# Minimal hyprland.conf skeleton for shell: $shell
# Generated by install-hypr-switch.sh

monitor=,preferred,auto,1

# Keybinds
bind = SUPER SHIFT, S, exec, hypr-switch
bind = SUPER, T, exec, $TERMINAL_CMD
bind = SUPER, L, exec, $LOCK_CMD
$EXIT_CONF_LINE

# Add your window rules, animations, and layout config below
SKEL
        fi
        echo "  [$shell] Generated new $filetype with keybinds pre-installed (including SUPER+T for terminal)."
    else
        # File exists already — inject only missing keybinds, never overwrite.
        if [[ "$filetype" == "hyprland.lua" ]]; then
            grep -q 'exec_cmd("hypr-switch")' "$target" || \
                echo "hl.bind(\"SUPER + SHIFT + S\", hl.dsp.exec_cmd(\"hypr-switch\"), { description = \"Switch Hyprland shell\" })" >> "$target"
            grep -qE 'exec_cmd\("(kitty|alacritty|foot|wezterm|konsole|gnome-terminal)"' "$target" || \
                echo "hl.bind(\"SUPER + T\", hl.dsp.exec_cmd(\"$TERMINAL_CMD\"), { description = \"Open terminal\" })" >> "$target"
            grep -qF "$LOCK_CMD" "$target" || \
                echo "hl.bind(\"SUPER + L\", hl.dsp.exec_cmd(\"$LOCK_CMD\"), { description = \"Lock screen\" })" >> "$target"
            grep -q 'hl.dsp.exit()\|uwsm stop' "$target" || \
                echo "$EXIT_LUA_LINE" >> "$target"
        else
            grep -q 'exec, hypr-switch' "$target" || \
                echo "bind = SUPER SHIFT, S, exec, hypr-switch" >> "$target"
            grep -qE 'exec, (kitty|alacritty|foot|wezterm|konsole|gnome-terminal)' "$target" || \
                echo "bind = SUPER, T, exec, $TERMINAL_CMD" >> "$target"
            grep -qF "$LOCK_CMD" "$target" || \
                echo "bind = SUPER, L, exec, $LOCK_CMD" >> "$target"
            grep -q 'exit,\|uwsm stop' "$target" || \
                echo "$EXIT_CONF_LINE" >> "$target"
        fi
        echo "  [$shell] Injected any missing keybinds into existing $filetype (nothing overwritten)."
    fi
done

# ---------------------------------------------------------------------------
# PATH setup (see setup_and_verify_path defined earlier). Called here for the
# normal flow, exactly as it's called in the no-shells-passed early exit
# above — this guarantees hypr-switch resolves and runs regardless of which
# shell (fish, bash, zsh) is actually in use, no matter which code path led
# here.
# ---------------------------------------------------------------------------
setup_and_verify_path

echo ""
echo "[6/6] Done."
echo ""
echo "== Install complete =="
echo "Script location: $SCRIPT_PATH"
echo "Configured shells: ${SHELL_NAMES[*]}"
if [[ "$BACKED_UP" == true ]]; then
    echo "Also preserved your pre-existing config as the 'default' shell."
fi
echo ""
echo "Create the initial active symlink with:"
echo "  hypr-switch ${SHELL_NAMES[0]}"
echo ""
echo "Remember: to add MORE shells later, you do NOT need to run this"
echo "installer again. Just create the folder and drop a config in it:"
echo "  mkdir -p $SHELLS_DIR/<name>"
echo "  cp /path/to/hyprland.lua $SHELLS_DIR/<name>/hyprland.lua"
echo "hypr-switch will discover it automatically on its next run."
