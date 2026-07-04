# hypr-switch

A lightweight, symlink-based shell switcher for [Hyprland](https://hyprland.org). Manage multiple Hyprland shells/dotfiles (e.g. `skwd`, `brainshell`, `HyDE`, `dots`, `celestial`) side by side, and switch between them instantly — no manually copying or overwriting config files ever again.

Works with **both** the legacy `hyprland.conf` (hyprlang) and the new `hyprland.lua` (Hyprland 0.55+) config formats, and any mix of the two across different shells.

Shells are **auto-discovered from disk every time `hypr-switch` runs.** There is no fixed list baked into the script at install time — add a new shell by creating a folder and dropping a config into it, and it's immediately available. No re-installing, no editing the script.

---

## Table of Contents

- [Why this exists](#why-this-exists)
- [How it works](#how-it-works)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Project structure](#project-structure)
- [Keybinds installed automatically](#keybinds-installed-automatically)
- [How logout/reload actually works](#how-logoutreload-actually-works)
- [Adding a new shell later](#adding-a-new-shell-later)
- [Bringing in an existing dotfiles repo as a shell](#bringing-in-an-existing-dotfiles-repo-as-a-shell)
- [Checking the active shell](#checking-the-active-shell)
- [Uninstalling](#uninstalling)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [License](#license)

---

## Why this exists

If you like to experiment with different Hyprland shells/rices (HyDE, skwd, brainshell, celestial, jatoolkit, or your own dotfiles), the naive approach is to manually overwrite `~/.config/hypr/hyprland.conf` (or `.lua`) every time you want to switch. This is slow, error-prone, and risks accidentally destroying a config you haven't backed up.

`hypr-switch` solves this by keeping every shell's config in its own isolated folder, and using a **symlink** to tell Hyprland which one is currently active. Switching shells becomes a single command (or a keybind) that atomically swaps the symlink — nothing is ever overwritten or deleted.

---

## How it works

```
~/.config/hypr/
├── hyprland.lua -> shells/skwd/hyprland.lua      (this is a SYMLINK, not a real file)
├── .current_shell                                 (tracks which shell is active)
└── shells/
    ├── skwd/
    │   └── hyprland.lua
    ├── brainshell/
    │   └── hyprland.lua
    └── dots/
        └── hyprland.conf
```

- Each shell lives in its own folder under `~/.config/hypr/shells/<name>/`
- `~/.config/hypr/hyprland.lua` (or `.conf`) is **never a real file** — it's a symlink pointing at whichever shell is currently active
- **Every time `hypr-switch` runs, it scans `~/.config/hypr/shells/` fresh** and treats any folder containing a `hyprland.lua` or `hyprland.conf` as a valid switch target. Nothing about which shells exist is hardcoded or cached — this means adding, removing, or renaming a shell folder takes effect immediately, with zero re-installation
- The `hypr-switch` command deletes the old symlink and creates a new one pointing at the shell you choose, then logs you out so Hyprland restarts clean with the new config
- A `.current_shell` file tracks the active shell's name for reference (e.g. for a status bar module)

Because switching is just a symlink swap, it's instant and there is no risk of one shell's config bleeding into another.

The script also guards itself against accidentally being run under a non-bash POSIX shell (`sh`), which would otherwise fail silently before discovery even runs — see the troubleshooting entry below if `hypr-switch` ever produces no output at all.

---

## Requirements

- Hyprland (any recent version — both `hyprlang`/`.conf` and Lua/`.conf` configs are supported)
- `bash`
- `rofi` (used for the interactive picker menu — optional if you always pass a shell name directly)
- `notify-send` (usually part of `libnotify` — used for switch confirmation popups; hypr-switch still works without it, just silently)
- `uwsm` (optional — auto-detected and tried as part of the logout fallback chain; see [How logout/reload actually works](#how-logoutreload-actually-works))

Install the picker/notification dependencies on Arch if you don't have them:

```bash
sudo pacman -S rofi libnotify
```

---

## Installation

1. Clone this repository:

   ```bash
   git clone https://github.com/bobincraft1/hypr-switch.git
   cd hypr-switch
   ```

2. Make the scripts executable:

   ```bash
   chmod +x install-hypr-switch.sh hypr-switch
   ```

3. Run the installer. Passing shell names is **optional** — it's only used to generate skeleton configs for shells that don't have one yet.

   Install with no shells (just installs the `hypr-switch` command itself):
   ```bash
   ./install-hypr-switch.sh
   ```

   Install and generate skeletons for one or more shells:
   ```bash
   ./install-hypr-switch.sh skwd brainshell
   ```

   The installer does not just copy the file and assume it worked. It verifies, in order: the copy actually landed and matches the source byte-for-byte, the executable bit is actually set (not just that `chmod` returned success), and that `hypr-switch` genuinely runs (`hypr-switch --help`) — catching issues like `noexec`-mounted filesystems or Windows line endings before they become a confusing "command not found" later. It then checks whether `~/.local/bin` is on `PATH`, and if not, patches the config file for **whichever shell you actually have** — `fish`, `bash`, and `zsh` are all handled, not just one — and verifies afterward that `hypr-switch` actually resolves by name. If any of this fails, the installer prints a specific error explaining what to do rather than reporting false success. This all works correctly even if the installer itself is invoked through a non-bash shell.

4. **If you already have a working Hyprland config** at `~/.config/hypr/hyprland.lua` or `~/.config/hypr/hyprland.conf` — a real file, from before you started using hypr-switch — the installer automatically preserves it rather than leaving it invisible and unmanaged:

   - It's moved into `~/.config/hypr/shells/default/`, with its content and filename completely unchanged
   - The original location is replaced with a symlink pointing at the new location, so **your current setup keeps working immediately** — nothing about your actual config changes, only where the file physically lives
   - `default` immediately shows up as a normal shell in `hypr-switch --list`, with no extra registration required, since shell discovery is purely filesystem-based

   This only happens once. If `~/.config/hypr/hyprland.lua`/`.conf` is already a symlink (e.g. hypr-switch created it on an earlier run, or you already switched shells at least once), it's left alone — the installer explicitly checks `! -L` (not a symlink) before touching anything, specifically so this step can never re-process or clobber a config hypr-switch is already managing. Re-running the installer is always safe.

   If you have no pre-existing config (a fresh Hyprland install), this step does nothing and prints a short confirmation that there was nothing to back up — it's not an error.

5. If a shell name you passed doesn't have an existing config yet, the installer will ask:

   ```
   No config found for 'dots'.
     Generate a new one as .lua or .conf? [lua/conf]:
   ```

   Answer `lua` or `conf` and a minimal, working skeleton config is generated for you automatically, with the switcher, terminal, lock, and logout keybinds already installed.

6. If a shell name you passed **does** already have a config sitting in `~/.config/hypr/shells/<name>/`, the installer detects it and injects only the missing keybinds — nothing you've already written is touched or overwritten.

7. Create the initial active symlink (pick whichever shell you want to boot into first):

   ```bash
   hypr-switch skwd
   ```

   This will log you out. Log back in and you'll be in the `skwd` shell.

   If your pre-existing config was preserved as `default` in step 4, you can switch straight back to exactly what you had before at any time with:
   ```bash
   hypr-switch default
   ```

That's it — installation is complete.

---

## Usage

### Switch via interactive picker (rofi)

```bash
hypr-switch
```

This opens a rofi menu listing every shell currently found under `~/.config/hypr/shells/`. Select one and press Enter.

### Switch directly by name

```bash
hypr-switch skwd
hypr-switch brainshell
hypr-switch dots
```

### List all discovered shells

```bash
hypr-switch --list
```

### Reload the current shell's config without switching or logging out

```bash
hypr-switch --reload
```

Useful after editing the active shell's config file directly — tries `hyprctl reload` first (works for most non-structural config changes), and does not touch the symlink or trigger a logout.

### Show usage and discovered shells

```bash
hypr-switch --help
```

### What happens when you switch shells

1. The script re-scans `~/.config/hypr/shells/` and validates the shell name exists
2. It confirms the target config file is actually present on disk
3. If you're already on that shell, it does nothing and tells you so
4. It removes the current `hyprland.lua`/`hyprland.conf` symlink (both filenames are checked, so switching between a `.lua` shell and a `.conf` shell is always clean)
5. It creates a new symlink pointing at the chosen shell's config
6. It records the active shell name in `~/.config/hypr/.current_shell`
7. It sends a desktop notification confirming the switch
8. It logs you out using a fallback chain of methods — see the next section

You'll need to log back in through your greeter/TTY after switching — this is intentional. Some shells use different plugins, bar processes (waybar/quickshell/etc.), and `exec-once` daemons, so a full clean restart avoids leftover processes from the previous shell conflicting with the new one.

---

## Project structure

```
hypr-switch/
├── hypr-switch                # The switcher command itself — copied as-is to ~/.local/bin
├── install-hypr-switch.sh     # Installs hypr-switch, optionally generates skeleton configs
├── uninstall-hypr-switch.sh   # Removes hypr-switch cleanly
└── README.md                  # This file
```

After installation, the following is created on your system (not part of this repo):

```
~/.local/bin/hypr-switch                  # the switcher command (a direct copy — no templating)
~/.config/hypr/shells/<name>/...          # one folder per shell — add/remove freely, anytime
~/.config/hypr/hyprland.lua|.conf         # symlink to the active shell
~/.config/hypr/.current_shell             # plain text file, active shell's name
```

Note the important architectural change from earlier versions: `hypr-switch` is copied to `~/.local/bin` **verbatim**, with no shell list baked into it at install time. All shell knowledge lives entirely in the filesystem layout under `~/.config/hypr/shells/`, discovered fresh on every run.

---

## Keybinds installed automatically

Every shell config (whether freshly generated or an existing one you brought in) gets these keybinds added if they aren't already present:

| Action | Lua syntax | conf syntax |
|---|---|---|
| Open shell switcher | `hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("hypr-switch"), { description = "Switch Hyprland shell" })` | `bind = SUPER SHIFT, S, exec, hypr-switch` |
| Open terminal | `hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"), { description = "Open terminal" })` | `bind = SUPER, T, exec, kitty` |
| Lock screen | `hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.local/share/quickshell-lockscreen/lock.sh"), { description = "Lock screen" })` | `bind = SUPER, L, exec, ~/.local/share/quickshell-lockscreen/lock.sh` |
| Logout | `hl.bind("SUPER + SHIFT + E", hl.dsp.exit(), { description = "Logout" })` or `hl.dsp.exec_cmd("uwsm stop")` | `bind = SUPER SHIFT, E, exit,` or `exec, uwsm stop` |

**Terminal:** the skeleton defaults to `kitty`. If you use a different terminal (`alacritty`, `foot`, `wezterm`, `konsole`, etc.), edit that keybind line directly in each shell's config after install. When injecting into an *existing* config, the installer checks for common terminal emulator names already bound and skips adding a duplicate `SUPER + T` bind if one seems to already exist — but always verify manually, since this check is a convenience heuristic, not a guarantee.

**Lock screen:** the path assumes [quickshell-lockscreen](https://github.com/quickshell-mirror). If you use a different locker (`hyprlock`, `swaylock`, etc.), edit that keybind line after install.

**Logout keybind vs. what actually runs on switch:** the keybind above is a simple, single-method convenience bind for manually logging out without switching shells. It is **not** what `hypr-switch` itself uses internally when you actually switch shells — that logic is more robust and lives inside the script itself. See the next section.

---

## How logout/reload actually works

This is a deliberate design point worth explaining clearly, since it was a specific fix from earlier versions of this project — including one real, confirmed incident (see the warning below).

**The logout logic is NOT just a keybind that assumes one command works.** It lives inside the `hypr-switch` script itself, as a bash function (`attempt_logout`) that is executed as part of every switch — regardless of which shell, which keybind, or whether you triggered it from the rofi picker or the CLI. It tries methods in order, moving to the next only if the current one fails:

1. **`uwsm stop`** — tried first if `uwsm` is installed and currently running. This is the wiki-recommended method for uwsm-managed sessions, since it brings down the whole graphical + login session in the correct order rather than pulling Hyprland out from underneath it.
2. **`hyprctl dispatch 'hl.dsp.exit()'`** — the correct native syntax for Hyprland 0.55+ Lua configs. (Note: the older bare `hyprctl dispatch exit` — without `hl.dsp.` — is hyprlang-only and is rejected under Lua configs with an `expected a dispatcher` error.)
3. **`hyprctl dispatch exit`** — legacy hyprlang syntax, tried as a fallback for setups still fully on `.conf`/hyprlang rather than Lua.

If **both** methods fail, `hypr-switch` does not fail silently — the shell config has already been switched successfully at this point, but you'll get an explicit critical notification and a message telling you to log out manually, so you're never left wondering whether anything happened.

> **⚠️ Removed: `loginctl terminate-user ""` as a 4th fallback.**
> An earlier version of this script included a fourth, last-resort fallback using `loginctl terminate-user ""`. This has been **permanently removed** after a confirmed incident where it caused a full system shutdown/poweroff instead of a simple logout.
>
> The reason: an empty string as the argument to `terminate-user` is real, documented systemd syntax meaning "the calling user's entire session" — it is not a typo, placeholder, or harmless no-op. On a single-user desktop machine, terminating the entire session this way can legitimately cascade through logind's session-stop chain and, depending on your system's power management configuration, end in a full poweroff rather than dropping you back to a login screen.
>
> A logout helper should never risk that outcome. `hypr-switch` now stops after exhausting the two well-defined, narrowly-scoped `hyprctl` methods above, rather than reaching for a broader systemd primitive it can't fully control the blast radius of. If you were relying on this old fallback, do not add it back — log out manually instead if the two safer methods above ever both fail.

`hypr-switch --reload` uses a separate, smaller fallback chain (`hyprctl reload`, then the Lua dispatcher equivalent) for in-place config reloads that don't require a full logout at all, and never touches `uwsm` or any systemd session commands.

---

## Adding a new shell later

**You do not need to re-run the installer.** This was a specific limitation in earlier versions that has been fixed — `hypr-switch` discovers shells directly from the filesystem on every invocation, so adding one is just:

```bash
mkdir -p ~/.config/hypr/shells/celestial
cp /path/to/your/hyprland.lua ~/.config/hypr/shells/celestial/hyprland.lua
```

Then immediately:
```bash
hypr-switch celestial
```

It works right away — no script re-run, no re-templating, nothing to forget.

If you'd like the convenience of auto-generating a *skeleton* config (with the standard keybinds pre-installed) rather than bringing your own, you can still optionally run the installer with just that new shell's name:

```bash
./install-hypr-switch.sh celestial
```

This only touches `celestial` — every other shell you already have is left completely alone.

---

## Bringing in an existing dotfiles repo as a shell

If you want a shell to be a full existing rice (e.g. someone's public dotfiles) rather than the minimal generated skeleton:

1. Clone or copy that config into the shell's folder:

   ```bash
   mkdir -p ~/.config/hypr/shells/celestial
   git clone https://github.com/someuser/celestial-dots.git /tmp/celestial-dots
   cp /tmp/celestial-dots/hyprland.lua ~/.config/hypr/shells/celestial/hyprland.lua
   # copy over any other files that config depends on (waybar, scripts, etc.) as needed
   ```

2. It's immediately usable:

   ```bash
   hypr-switch celestial
   ```

3. Optionally, run the installer for that shell name if you also want the standard switcher/terminal/lock/logout keybinds injected into it (only added if missing, never overwriting anything):

   ```bash
   ./install-hypr-switch.sh celestial
   ```

---

## Checking the active shell

```bash
cat ~/.config/hypr/.current_shell
```

To confirm the actual symlink target (useful for debugging):

```bash
ls -la ~/.config/hypr/hyprland.lua
# or
ls -la ~/.config/hypr/hyprland.conf
```

You should see an arrow (`->`) pointing at the shell folder currently in use.

To see every shell hypr-switch currently recognizes:

```bash
hypr-switch --list
```

---

## Uninstalling

```bash
chmod +x uninstall-hypr-switch.sh
./uninstall-hypr-switch.sh
```

This removes the `hypr-switch` command, the `.current_shell` tracker, and the active symlink (never a real file — the uninstaller checks with `-L` before removing anything from `~/.config/hypr`). You'll be asked whether to also delete all shell configs in `~/.config/hypr/shells/`, or keep them for future use.

After uninstalling, you must manually point Hyprland at a real config again before your next login:

```bash
ln -sf ~/.config/hypr/shells/<name>/hyprland.lua ~/.config/hypr/hyprland.lua
```

If you chose to keep your shell configs during uninstall and your original pre-hypr-switch config was auto-backed-up as `default` at install time (see [Installation](#installation), step 4), it's still sitting safely at `~/.config/hypr/shells/default/` — nothing is deleted by choosing to keep configs, only the now-dangling symlink is removed. Restore it as a real file directly, rather than a symlink, if you're leaving hypr-switch behind for good:

```bash
mv ~/.config/hypr/shells/default/hyprland.lua ~/.config/hypr/hyprland.lua
# or hyprland.conf, whichever filetype it is
```

---

## Troubleshooting

**`hypr-switch --list` (or any command) prints nothing at all, no error, no output**
This was a real bug found and fixed: if `hypr-switch` is ever invoked through a POSIX shell (`sh`) instead of `bash` — which can happen depending on how a keybind, launcher, or exec wrapper spawns commands, regardless of the `#!/usr/bin/env bash` shebang at the top of the file — the script used to die immediately and silently at `set -uo pipefail`, since plain `sh` doesn't support the `pipefail` option. This looked exactly like "only remembers one shell" or "forgets shells I added," because nothing after that line ever ran, including discovery.

This is fixed in the current version