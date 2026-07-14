# hypr-switch v2

A capture-based configuration switcher for [Hyprland](https://hyprland.org). Manage multiple Hyprland shells/rices (skwd, brainshell, HyDE, custom dotfiles, etc.) side by side — including everything they touch beyond just `hyprland.lua`: kitty, rofi, waybar, fastfetch, and a curated set of dotfiles directly in `$HOME` like `.zshrc`.

**This is a ground-up architectural rewrite, not an update to v1.** v1 only ever managed a single `hyprland.lua`/`.conf` symlink. v2 captures *everything a shell's installer actually touches*, using a before/after snapshot rather than a fixed list of apps. If you have v1 installed, see [Coming from v1](#coming-from-v1) before installing this.

---

## Table of Contents

- [Why this exists](#why-this-exists)
- [How it works](#how-it-works)
- [What gets watched, and what never will be](#what-gets-watched-and-what-never-will-be)
- [Installation](#installation)
- [The capture workflow](#the-capture-workflow)
- [Command reference](#command-reference)
- [Switching and the 'default' fallback](#switching-and-the-default-fallback)
- [A known, deliberate edge case: orphaned app folders](#a-known-deliberate-edge-case-orphaned-app-folders)
- [Safety mechanisms — what's actually verified, not assumed](#safety-mechanisms--whats-actually-verified-not-assumed)
- [Symlink semantics this project depends on](#symlink-semantics-this-project-depends-on)
- [Uninstalling](#uninstalling)
- [Coming from v1](#coming-from-v1)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [License](#license)

---

## Why this exists

Hyprland "shells" or rices are rarely just a `hyprland.lua`/`.conf` file. Their install scripts routinely touch `~/.config/kitty`, `~/.config/rofi`, `~/.config/waybar`, `~/.config/fastfetch`, and sometimes dotfiles directly in your home directory like `.zshrc` or `.themes`. Switching between such shells by hand means either manually tracking every file each one touches, or accepting that switching shells will leave a mess of half-mixed configs behind.

hypr-switch v2 solves this by capturing **whatever a shell's real installer actually changes** — nothing assumed, nothing hardcoded — and storing each shell's captured files in complete isolation, so switching is a clean, instant symlink swap across every app the shell touches at once.

---

## How it works

### Storage location

```
~/.hypr-switch/
├── shells/
│   ├── default/
│   │   └── configs/
│   │       ├── config/           <- mirrors things normally under ~/.config
│   │       │   ├── hypr/
│   │       │   ├── kitty/
│   │       │   ├── rofi/
│   │       │   └── fastfetch/
│   │       └── home/             <- mirrors a curated set of dotfiles in $HOME
│   │           ├── .zshrc
│   │           ├── .bashrc
│   │           └── .themes/
│   └── skwd/
│       └── configs/
│           ├── config/
│           │   ├── hypr/
│           │   ├── kitty/
│           │   └── waybar/
│           └── home/
│               └── .zshrc
├── .current_shell
└── .capture_state/               <- only exists while a capture is in progress
```

Storage lives at **`~/.hypr-switch`, deliberately outside `~/.config`.** This isn't arbitrary: if hypr-switch's own storage lived inside `~/.config/hypr`, and `~/.config/hypr` itself needs to become a symlink pointing into that storage (since `hypr` is captured like any other app), you'd get a folder trying to contain the very thing it's a symlink to — a structural contradiction. Keeping storage as a sibling of `~/.config`, in your home directory directly (similar to how `~/.ssh` or `~/.gnupg` work), avoids this entirely and means no exclusion rule anywhere has to remember to skip hypr-switch's own directory — it simply isn't reachable from inside `~/.config` at all.

### The symlink invariant

After installation, **every top-level entry under `~/.config`, and every watched dotfile in `$HOME`, is always a symlink** pointing into `~/.hypr-switch/shells/<active-shell>/configs/...`. Nothing under those locations is ever a real, standalone file or directory while hypr-switch is installed — this is enforced consistently by every command, and is what makes an instant, atomic-feeling switch possible: switching shells is just re-pointing a handful of symlinks, not copying or diffing anything.

### The problem this raises, and how it's solved

If `~/.config/kitty` is currently a symlink into `default`'s storage, and you run some other shell's installer while `default` is still active, the installer would write straight through that symlink — silently corrupting `default`'s stored baseline. This was verified directly, not assumed:

```
$ ln -s storage/kitty live/kitty
$ rm live/kitty && cp -a storage/kitty live/kitty   # de-symlink to a real copy
$ echo "modified" > live/kitty/kitty.conf            # installer writes here
$ cat storage/kitty/kitty.conf                       # original storage:
kitty content v1                                      # ...completely untouched
```

This is why `capture-start` **de-symlinks every currently-managed item into a real, writable copy** before you run a shell's actual installer. The installer writes to real files, never through a shared symlink, so whatever was previously active (almost always `default`) can never be corrupted by someone else's install script — confirmed by direct testing, not just design intent.

### The capture sequence

1. **`capture-start <name>`** — snapshots a SHA-256 hash of every watched file, then de-symlinks everything into real copies
2. **You run the shell's real installer yourself**, completely normally, exactly as its own instructions say — hypr-switch does not hijack, intercept, or wrap it in any way
3. **`capture-finish <name>`** — re-hashes everything, diffs against the "before" snapshot, groups every changed file by its top-level app folder (or, for a single dotfile like `.zshrc`, by the file itself), moves each changed group into `<name>`'s storage, and symlinks it back
4. Anything **not** touched by the diff is restored to exactly whatever it pointed at before — untouched, unclaimed, left alone

---

## What gets watched, and what never will be

### Watched: `~/.config`, unconditionally

Every top-level entry under `~/.config` is fair game for capture. This is safe because `~/.config` is, by long-standing convention, specifically for application configuration — not credentials, not personal documents.

### Watched: a curated, explicit list in `$HOME`

Hyprland rices commonly also touch a handful of dotfiles directly in your home directory, outside `~/.config` entirely — this was confirmed by checking actual, current Hyprland dotfiles repositories rather than assumed generically. The default watch list:

```bash
WATCHED_HOME_ITEMS=(
    ".zshrc"
    ".bashrc"
    ".zshenv"
    ".bash_profile"
    ".themes"
    ".icons"
)
```

This is a fixed array near the top of the `hypr-switch` script — edit it directly if your shells touch something not listed here. **This list is deliberately never auto-expanded or inferred** — `$HOME` is never scanned wholesale, only these exact named entries are ever looked at, because `$HOME` also contains things like SSH keys and cloud credentials that must never be swept into a capture by accident.

### Never watched, under any circumstances: the denylist

```bash
DENYLIST_HOME_ITEMS=(
    ".ssh" ".gnupg" ".gpg" ".password-store" ".aws" ".gcloud" ".kube"
    ".netrc" ".git-credentials" ".docker" ".hypr-switch"
)
```

This is a hardcoded backstop, checked even against the curated watch list above — so even a careless edit to `WATCHED_HOME_ITEMS` can't accidentally reintroduce something dangerous. There's also a case-insensitive pattern check that blocks any watched item whose name contains `key`, `credential`, `secret`, or `token`, as a second layer of defense. This was directly tested: `.my_api_key` and `.SECRET_tokens` are both correctly blocked even though neither is explicitly named in the denylist array.

### Never watched: everything else in `$HOME`

Anything in `$HOME` not explicitly named in `WATCHED_HOME_ITEMS` — your Documents, Downloads, browser profiles, unrelated app data in `~/.local/share`, and so on — is never touched, never scanned, and never has any bearing on hypr-switch's behavior at all.

### `.git` directories

Any directory named `.git` encountered while hashing is excluded from the diff (via `find -path "*/.git" -prune`), **and** explicitly stripped out after any move into storage — so if some installer `git clone`s straight into a config folder, you don't end up with repo history duplicated into every shell that happens to claim that folder.

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

3. Run the installer:
   ```bash
   ./install-hypr-switch.sh
   ```

   This does four things, each independently verified rather than assumed to have worked:
   - Copies `hypr-switch` to `~/.local/bin`, verifying the copy is byte-identical, the executable bit is genuinely set, and the script genuinely runs (`--help` is actually invoked, not just checked for existence) — catches `noexec`-mounted filesystems or corrupted copies immediately rather than surfacing as a confusing "command not found" later
   - Patches **whichever of fish, bash, or zsh are actually present** on your system so `~/.local/bin` is on `PATH` — not just one, all three are checked independently — then re-verifies `hypr-switch` genuinely resolves by name afterward
   - Runs the one-time `bootstrap`: captures your **entire current `~/.config`**, plus any currently-existing watched dotfiles, into a shell called `default` — this is your safety net, a complete snapshot of what you had before hypr-switch ever touched anything
   - Reports exactly what got captured

   The installer itself is guarded to run correctly under bash even if something invokes it via a plain POSIX `sh` — confirmed directly: `sh ./install-hypr-switch.sh` completes successfully end-to-end, re-executing itself under real bash before any bash-only syntax runs.

4. If this is the first time `~/.local/bin` was added to your `PATH`, open a **new terminal window** — PATH changes in shell config files only take effect in new sessions.

5. Confirm it worked:
   ```bash
   hypr-switch --list
   ```
   You should see `default` listed, with however many items it captured.

Re-running the installer at any time is always safe — every step is idempotent.

---

## The capture workflow

To bring in a new shell (say, `skwd`):

```bash
hypr-switch capture-start skwd
```

This de-symlinks everything currently managed into real, writable copies, and snapshots their current state. You'll see output like:
```
De-symlinked 7 item(s).
Ready. Now run 'skwd''s actual installer normally, exactly as its own instructions say.
```

Now **run skwd's real installer**, exactly as its own README says — clone its dotfiles repo, run its install script, whatever it normally asks for. hypr-switch does nothing during this step.

When it's done:

```bash
hypr-switch capture-finish skwd
```

This re-snapshots everything, diffs against the "before" state, and reports exactly what changed:
```
Claimed for 'skwd':
  - config/kitty
  - config/rofi
  - config/waybar
  - home/.zshrc

  captured: config/kitty
  captured: config/rofi
  captured: config/waybar
  captured: home/.zshrc

Capture finished for 'skwd'. 4 item(s) captured.
```

Only what actually changed is captured — `fastfetch`, `hypr`, `.bashrc`, and `.themes` in this example were never touched by skwd's installer, so they're left exactly as they were (still pointing at `default`).

The captured items are live immediately so you can inspect them, but you're not formally "on" skwd until you run:

```bash
hypr-switch skwd
```

which commits to it fully (re-pointing every symlink consistently, including anything skwd doesn't own falling back to `default`) and logs you out to apply it.

### If something goes wrong mid-capture

```bash
hypr-switch capture-cancel
```

Reverts everything de-symlinked back to its original symlink, and relocates (never deletes) anything the installer created during the aborted attempt into `~/.hypr-switch/.cancelled/<name>-<timestamp>/` for manual recovery if you want it.

### Checking progress

```bash
hypr-switch capture-status
```

---

## Command reference

```
hypr-switch                       interactive picker (rofi)
hypr-switch <name>                switch to shell <name>
hypr-switch --list                list discovered shells
hypr-switch --reload              reload current config, no logout, no switch
hypr-switch --help                show usage
hypr-switch bootstrap             one-time whole-config capture as 'default' (usually run by the installer)
hypr-switch capture-start <name>  begin capturing a new/updated shell
hypr-switch capture-finish <name> finish capturing — diff, claim, move, symlink
hypr-switch capture-cancel        abort an in-progress capture, restore everything
hypr-switch capture-status        show whether a capture is in progress
hypr-switch show <name>           list exactly what a shell owns
```

---

## Switching and the 'default' fallback

When you switch to a shell, hypr-switch computes what that shell should look like as: **everything `default` owns, with anything the target shell explicitly owns overriding it.** This means a shell doesn't need to re-capture apps it never touches — `fastfetch`, for instance, will transparently keep using `default`'s copy for every shell that never customized it.

Concretely, switching:
- Re-points every symlink the target shell (or `default`, as fallback) owns
- Skips anything already correctly pointed (no unnecessary churn)
- Refuses to touch anything that's unexpectedly a real file/directory instead of a symlink, printing a warning instead of risking data loss (this is a genuine safety net, verified directly: manually replacing a symlink with a real directory and switching shells correctly leaves that real directory completely untouched, printing a clear warning instead)
- Writes the new active shell name, sends a notification, and logs out via a fallback chain

---

## A known, deliberate edge case: orphaned app folders

If a shell's installer introduces an app `default` never had — say, `skwd` is the first shell to ever install `waybar` — then `waybar` only exists in `skwd`'s captured items, not `default`'s. If you later switch **back** to `default`, `~/.config/waybar` is **left exactly as it is** (still pointing at `skwd`'s copy), because `default` never claimed ownership of it and switching only touches folders that either `default` or the target shell explicitly owns.

This was a deliberate design choice, not an oversight: the alternative (removing or hiding folders neither shell currently discusses) risks unlinking something a third shell might still be actively using, in a way that's hard to reason about safely. It's confirmed directly through testing — after `skwd` introduces `waybar` and you switch back to `default`, `waybar` correctly still resolves to `skwd`'s copy rather than disappearing or erroring.

If this matters to you, you can manually capture `waybar` under `default` too (temporarily switch to default, then run a capture cycle that includes removing/reinstalling waybar's default state), or simply be aware that an app introduced by one shell will keep showing that shell's version until some other shell explicitly claims it too.

---

## Safety mechanisms — what's actually verified, not assumed

Every one of these was directly tested during development, not just designed and trusted:

- **De-symlink-before-install** prevents any installer from corrupting a previously-active shell's stored baseline — proven by direct before/after content comparison, not just architectural reasoning.
- **Independent re-verification pass** in `capture-finish`: for every de-symlinked item that the primary diff says is *unchanged*, a second, genuinely separate re-hash of the live filesystem (not a re-run of the same in-memory comparison) is checked before anything is discarded. If they disagree, the item is captured defensively rather than silently thrown away — this exists specifically so a bug in the primary diff logic can't cause silent data loss.
- **The real-directory-instead-of-symlink guard**, both in `do_switch` and throughout the capture commands: if something hypr-switch expects to be a symlink is unexpectedly a real file or directory, it's left completely alone with a warning, never destroyed or overwritten.
- **The `ln`/`mv`-against-an-existing-directory gotcha** is explicitly guarded against everywhere in this project. Both `ln -sf` and `mv`, when their target is an *existing real directory*, silently nest **inside** that directory instead of replacing it — this is standard GNU coreutils behavior, confirmed directly:
  ```
  $ ln -sf real_target real_existing_dir    # real_existing_dir already exists as a dir
  $ ls real_existing_dir/
  real_target -> ...                          # nested inside, NOT replaced — the gotcha
  ```
  Every single `ln -s` and `mv` call in this project is preceded by an explicit existence check and removal, so this can never silently happen.
- **`.git` exclusion** applies both to hashing (so repo metadata never pollutes diffs) and to physical moves (so it's never duplicated into storage either) — confirmed as two genuinely separate fixes, since excluding something from hashing does not automatically exclude it from a whole-folder `mv`.
- **Broken symlinks are never silently invisible.** An early version of this project had a real bug here: bash's `-e` test returns false for a broken symlink (since it follows the link and checks the *target*), which meant a simple `[[ -e "$entry" ]] || continue` filter — used in several places to iterate live config — silently skipped broken symlinks entirely, before any of the explicit broken-symlink handling code could ever run. This was caught by deliberately constructing a broken symlink during testing and confirming the expected warning didn't print. Every such filter now checks `-e || -L`, and broken symlinks get an explicit, visible warning rather than vanishing from consideration.
- **`shopt -s dotglob`** is set globally, because every single watched home-scope item (`.zshrc`, `.bashrc`, etc.) starts with a dot, and bash's bare `*` glob does **not** match dotfiles by default. An early version of this project had `--list` and `show` silently omitting every home-scope item because of this — caught directly by testing, not assumed correct. Confirmed separately that enabling `dotglob` never causes a glob to match `.` or `..` themselves, so this is safe.
- **The bash self-guard**, in both `hypr-switch` and the installer: if either script is ever invoked through a plain POSIX `sh` rather than bash — which can happen depending on how a caller spawns a command, regardless of the file's own `#!/usr/bin/env bash` shebang — associative arrays, substring expansion, and other bash-only syntax used throughout would otherwise fail immediately and silently. Both scripts detect this (`$BASH_VERSION` unset) and transparently re-exec themselves under real bash before anything else runs. Confirmed directly: `sh ./install-hypr-switch.sh` completes the entire install successfully.
- **No dangerous logout fallback.** The logout chain tries `uwsm stop`, then Hyprland's native Lua exit dispatcher, then the legacy hyprlang exit dispatcher — and stops there. An earlier related project once included a fourth fallback, `loginctl terminate-user ""`, which is real, documented systemd syntax for "terminate the calling user's entire session" — on a single-user desktop, this can cascade into a full system shutdown rather than a simple logout. That method is deliberately absent here.
- **`capture-cancel` never duplicates unmodified content into the holding area.** Since `capture-start` unconditionally de-symlinks *every* managed item regardless of whether it ends up being touched, an early version of `capture-cancel` relocated *all* of them into `.hypr-switch/.cancelled/` on every cancel — even items nothing had changed, which are already safely stored, byte-identical, at their original location. Caught directly by testing: cancelling a capture where literally nothing was modified still produced a "preserved at ..." message and a populated holding folder. Fixed by comparing each de-symlinked item against its original with `diff -rq` before deciding whether to relocate it (genuinely different) or just discard it directly (identical, nothing lost).
- **No empty shell folders left behind.** If `capture-finish` detects zero actual changes, it no longer creates `shells/<name>/configs/` at all — an earlier version unconditionally created this directory structure regardless of whether anything was captured into it, leaving permanent empty clutter after a no-op capture attempt.

---

## Symlink semantics this project depends on

These were verified empirically against this environment's actual GNU coreutils behavior, not assumed from general knowledge, since getting any of them wrong would risk real data loss:

| Behavior | Verified result |
|---|---|
| `ln -sf TARGET EXISTING_DIR` | Nests **inside** `EXISTING_DIR` rather than replacing it — the classic gotcha. Guarded against everywhere with an explicit pre-removal check. |
| `mv SRC EXISTING_DIR` | Same nesting behavior as `ln -sf`. Every `mv` in this project checks the destination doesn't already exist first. |
| `readlink -f` on absolute vs. relative symlinks to the same target | Canonicalizes identically either way — safe to use for comparing whether two symlinks point at the same place. |
| `find -L` with `-prune` | Correctly stops descent into a pruned path even when following symlinks — confirmed a pruned symlinked directory is never traversed. |
| `find -L /path/to/symlink` where the *root path itself* is a symlink | Correctly follows it and traverses the target's contents — confirmed this works even when the symlink is the starting argument, not just one encountered mid-traversal. |
| `sha256sum` output format | Exactly 64 hex characters, then a 2-character separator, then the filename — confirmed byte-for-byte, since this project's hash-file parsing relies on fixed-width substring extraction rather than word-splitting (to correctly handle filenames containing spaces). |
| `rm -f` on a symlink pointing at a directory | Removes the symlink itself without needing `-r` and without ever touching or descending into the target — confirmed the target directory and its contents survive completely untouched. |
| `[[ -e "$path" ]]` on a broken symlink | Returns **false** (follows the link, target doesn't exist) — this is the exact bug described above. `[[ -L "$path" ]]` correctly still detects it as a symlink regardless of whether the target exists. |
| `grep -F` combined with a `$` "end of line" pattern | **Does not work as an anchor** — `-F` treats `$` as a literal character, not a regex anchor. An earlier version of this project's re-verification logic used exactly this broken pattern, causing false-positive "changed" results for single-file items. Fixed by comparing via bash associative arrays instead of grep/regex entirely. |

---

## Uninstalling

```bash
chmod +x uninstall-hypr-switch.sh
./uninstall-hypr-switch.sh
```

Unlike a hypothetical simple removal, this **de-symlinks every currently-active item back into a real file or directory first**, preserving whatever content is currently live (not necessarily `default`'s — whatever shell you were actually on) — confirmed directly: uninstalling while on a shell with modified content correctly leaves that modified content behind as ordinary real files, not `default`'s original.

You'll then be asked whether to also delete `~/.hypr-switch` entirely (removing every other captured shell), or keep it for a future reinstall.

---

## Coming from v1

v1 only ever managed one file (`hyprland.lua`/`.conf`) and stored shells at `~/.config/hypr/shells/`. v2 is a different, incompatible architecture — different storage location (`~/.hypr-switch`), different capture model (diff-based across many apps, not folder-per-shell for one file). There is no automatic migration.

If you have v1 installed:
1. Uninstall v1 first (its own `uninstall-hypr-switch.sh`), or at minimum confirm its symlink at `~/.config/hypr/hyprland.lua` is resolved back to a real file
2. Then install v2 fresh — its `bootstrap` step will correctly capture whatever your `~/.config/hypr/hyprland.lua` looks like at that point, as part of the new `default`

---

## Troubleshooting

**`hypr-switch: command not found`**
Open a brand new terminal — PATH changes only apply to new sessions. If it still fails, re-run `./install-hypr-switch.sh` (safe to repeat) and check its PATH-verification output for a specific error.

**"No shells discovered yet"**
Run `hypr-switch bootstrap` — this should normally have run automatically during install; if it didn't (or was interrupted), running it manually is safe and idempotent.

**A capture seems stuck / `capture-start` refuses because "a capture is already in progress"**
Run `hypr-switch capture-status` to see what it's waiting on, then either `hypr-switch capture-finish <name>` or `hypr-switch capture-cancel`.

**Switching to a shell doesn't seem to change some app's config**
That app may not be owned by either the shell you're switching to or `default` — see [A known, deliberate edge case](#a-known-deliberate-edge-case-orphaned-app-folders). Check with `hypr-switch show <name>` to confirm exactly what a shell owns.

**A warning about a "real file/directory, not a symlink"**
Something outside hypr-switch modified `~/.config` or a watched dotfile directly, replacing a symlink with real content. hypr-switch will never overwrite this automatically — investigate manually, then either restore the symlink yourself or accept the real content as the new baseline by re-running a capture.

**Switching logs out but then Hyprland doesn't restart correctly**
This is a session/compositor issue unrelated to hypr-switch's symlink logic — confirm which logout method actually succeeded (the notification distinguishes success from "automatic logout failed").

**I edited `WATCHED_HOME_ITEMS` and it doesn't seem to take effect**
Changes to the array only affect *future* `bootstrap`/`capture-start`/`capture-finish` runs — items already captured under an existing shell aren't retroactively affected.

---

## FAQ

**Why isn't `$HOME` scanned wholesale instead of using a curated list?**
Because `$HOME` also contains SSH keys, cloud credentials, and password stores. A curated, explicit allowlist plus a hardcoded denylist backstop is the only way to be confident nothing sensitive is ever swept into a capture — see [What gets watched, and what never will be](#what-gets-watched-and-what-never-will-be).

**Can two shells share ownership of the same app?**
Not partially — ownership is all-or-nothing per app folder (or per dotfile). If a shell's installer touches any file inside `kitty/`, that shell claims the *entire* `kitty/` folder as captured, not just the specific files that changed.

**What happens to `.zshrc` if multiple shells append to it rather than replace it?**
Each shell's captured `.zshrc` reflects whatever was *live* at the moment it was captured — which includes anything a previously-captured shell already added. This is expected: capturing is always relative to the current baseline, not a pristine original, so appends compound across shells captured in sequence rather than each starting fresh.

**Does capturing require `sudo`?**
No — everything happens entirely within your own home directory.

**Can I inspect a shell's captured files directly?**
Yes: `~/.hypr-switch/shells/<name>/configs/` contains real files, browsable and editable like any other directory. Editing a file there while that shell is active edits the live config directly, since it's the same file the symlink points to.

---

## License

MIT — do whatever you want with this, no warranty provided.
