#!/usr/bin/env bash
#
# install-hypr-switch.sh
# Installer for hypr-switch v2 — capture-based, multi-app config switcher.
# https://github.com/bobincraft1/hypr-switch
#
# This installer's jobs, in order, each independently verified rather than
# assumed to have worked:
#   1. Install the hypr-switch command to ~/.local/bin
#   2. Confirm it's genuinely executable and genuinely runs
#   3. Make sure ~/.local/bin is on PATH for whichever shell(s) you use —
#      fish, bash, and zsh are all checked and patched, not just one
#   4. Confirm 'hypr-switch' actually resolves by name afterward
#   5. Run the one-time bootstrap: capture your ENTIRE current ~/.config,
#      plus a curated set of dotfiles in $HOME, as a shell called 'default'
#
# Safe to re-run at any time: steps 1-4 are idempotent, and bootstrap
# no-ops if 'default' already exists.
#
# --- Bash self-guard --------------------------------------------------------
# Same reasoning as hypr-switch itself: this script uses bash-only syntax
# and must not silently fail if invoked via a POSIX sh.
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
BIN_DIR="$HOME/.local/bin"
SCRIPT_PATH="$BIN_DIR/hypr-switch"

echo "== hypr-switch v2 installer =="

mkdir -p "$BIN_DIR"

# ---------------------------------------------------------------------------
# 1. Install the standalone hypr-switch script — copy, chmod, and VERIFY
#    each step rather than assuming success.
# ---------------------------------------------------------------------------
if [[ ! -f "$SCRIPT_DIR/hypr-switch" ]]; then
    echo "ERROR: hypr-switch script not found next to this installer (expected: $SCRIPT_DIR/hypr-switch)" >&2
    exit 1
fi

cp "$SCRIPT_DIR/hypr-switch" "$SCRIPT_PATH"
if [[ ! -f "$SCRIPT_PATH" ]]; then
    echo "ERROR: copy to $SCRIPT_PATH did not produce a file. Check permissions on $BIN_DIR." >&2
    exit 1
fi
if ! cmp -s "$SCRIPT_DIR/hypr-switch" "$SCRIPT_PATH"; then
    echo "ERROR: copied file at $SCRIPT_PATH does not match the source. Copy may have been truncated." >&2
    exit 1
fi

chmod +x "$SCRIPT_PATH"
if [[ ! -x "$SCRIPT_PATH" ]]; then
    echo "ERROR: $SCRIPT_PATH exists but is still not executable after chmod +x." >&2
    echo "This can happen on filesystems mounted 'noexec' (some /tmp, network shares)." >&2
    exit 1
fi

if ! "$SCRIPT_PATH" --help >/dev/null 2>&1; then
    echo "ERROR: $SCRIPT_PATH was copied and made executable, but running it failed." >&2
    echo "Common causes: Windows line endings (CRLF), or bash not installed." >&2
    echo "Try:  sed -i 's/\r\$//' \"$SCRIPT_PATH\"   (fixes CRLF line endings)" >&2
    exit 1
fi

echo "[1/3] Installed hypr-switch to $SCRIPT_PATH — copy verified, executable bit verified, execution verified."

# ---------------------------------------------------------------------------
# 2. PATH setup — patches fish, bash, AND zsh configs (whichever are
#    present), then verifies 'hypr-switch' actually resolves by name.
# ---------------------------------------------------------------------------
echo ""
echo "[2/3] Checking PATH..."

path_already_ok=false
case ":$PATH:" in
    *":$BIN_DIR:"*) path_already_ok=true ;;
esac

if [[ "$path_already_ok" == true ]]; then
    echo "  $BIN_DIR is already on PATH for this session."
else
    echo "  $BIN_DIR is not on PATH yet — patching shell config file(s)."
    patched_any=false
    shell_detected=false

    if command -v fish >/dev/null 2>&1; then
        shell_detected=true
        if fish -c "fish_add_path $BIN_DIR" 2>/dev/null; then
            echo "  [fish] Added $BIN_DIR via fish_add_path (persists automatically)."
            patched_any=true
        else
            echo "  [fish] fish_add_path failed — add manually: fish_add_path $BIN_DIR" >&2
        fi
    fi

    if command -v bash >/dev/null 2>&1; then
        shell_detected=true
        bashrc="$HOME/.bashrc"
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

    if command -v zsh >/dev/null 2>&1; then
        shell_detected=true
        zshrc="$HOME/.zshrc"
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

    if [[ "$shell_detected" == false ]]; then
        echo "  WARNING: could not detect fish, bash, or zsh to patch automatically." >&2
        echo "  Add this line to your shell's config file manually:" >&2
        echo "    export PATH=\"$BIN_DIR:\$PATH\"" >&2
    elif [[ "$patched_any" == false ]]; then
        echo "  All detected shell configs already reference $BIN_DIR — nothing new to patch."
    fi
fi

export PATH="$BIN_DIR:$PATH"

if command -v hypr-switch >/dev/null 2>&1; then
    echo "  Verified: 'hypr-switch' resolves on PATH."
else
    echo "  ERROR: 'hypr-switch' still does not resolve on PATH even after patching." >&2
    echo "  This should not happen — please check your shell and PATH setup manually." >&2
fi

# ---------------------------------------------------------------------------
# 3. Bootstrap 'default' — one-time, whole-~/.config + curated-home capture.
#    Idempotent: no-ops automatically if already done.
# ---------------------------------------------------------------------------
echo ""
echo "[3/3] Bootstrapping 'default' from your current configuration..."
echo ""
"$SCRIPT_PATH" bootstrap

echo ""
echo "== Install complete =="
echo ""
echo "IMPORTANT: open a brand new terminal window before using 'hypr-switch'"
echo "if this is the first time ~/.local/bin was added to your PATH — changes"
echo "to shell config files only take effect in new sessions."
echo ""
echo "Next steps:"
echo "  hypr-switch --list                 confirm 'default' is there"
echo "  hypr-switch capture-start <name>   begin capturing a new shell"
echo "  hypr-switch --help                 full command reference"
