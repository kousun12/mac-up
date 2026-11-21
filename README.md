# mac-up

My new-Mac bootstrap for macOS 14 or later, on Apple Silicon or Intel. No Homebrew, Git, or existing developer tools are needed to start.

## Run it

Download and unzip a copy of this repo if Git isn't installed yet. In Terminal or Ghostty, `cd` to the extracted directory and run:

```sh
/bin/bash bootstrap.sh --dry-run
/bin/bash bootstrap.sh
```

Run as your normal logged-in user, not with `sudo`. The script only asks for admin access if it needs it to install an app in `/Applications` or apply an Apple Command Line Tools update. If the tools are missing, accept Apple's install dialog; mac-up does the rest of its work and exits with status 2 while the tools are pending. Rerun after the Apple installer finishes. Use `--skip-clt` to skip the installer/update check on a particular run.

At Rectangle's first launch, grant Accessibility permission in System Settings and choose the Rectangle preset if asked. If Rectangle was already running, quit it and rerun to apply shortcuts. Open a new tab for the zsh changes, and log out and back in for the input preferences.

For GitHub HTTPS remotes (including `ggpush`), mac-up configures `gh` as Git's credential helper if you're already signed in. On a fresh setup, sign in and enable it when you're ready:

```sh
gh auth login --hostname github.com --git-protocol https
gh auth setup-git --hostname github.com
```

This affects GitHub HTTPS credentials only; SSH remotes and your Git author identity are unchanged.

## What it sets up

| Area | Configuration |
| --- | --- |
| zsh | Login shell, persistent history (250,000 saved commands, 300,000 in memory), Ctrl-R fuzzy history search with a built-in fallback, syntax highlighting, and a compact directory/Git branch prompt. Appends one loader to `.zshrc`, backing up the existing file first. Loads `~/.bash_aliases`, seeded with `gst`, `gd`, `glog`, `gcm`, and `ggpush` only if the file is missing. |
| Dev tools | `nvm`, `uv`/`uvx`, [fx](https://fx.sh/), [ripgrep (`rg`)](https://github.com/BurntSushi/ripgrep), [jq](https://jqlang.org/), and [fzf](https://github.com/junegunn/fzf) for the current user. Also installs [GitHub CLI (`gh`)](https://cli.github.com/). `rg`, `jq`, `fzf`, and `gh` use pinned, checksum-verified upstream binaries. Does not install language runtimes or copy credentials. |
| Apps | [Ghostty](https://ghostty.org/), [Rectangle](https://rectangleapp.com/), and the current stable [Chrome](https://www.google.com/chrome/) from vendor disk images. Existing app bundles are left alone; use their built-in updaters. |
| Rectangle | The Rectangle preset plus the [saved overrides](config/rectangle-shortcuts.tsv), including Ctrl-Option-Left/Right for thirds and Ctrl-Option-F to maximize. |
| Input | Fast key repeat (`2`) with a short initial delay (`15`), mouse tracking `2`, trackpad tracking `3`, and Caps Lock as Control. |
| Apple tools | Installs via `xcode-select --install` on a fresh system; on subsequent runs selects only the latest stable CLT update listed by Apple for that Mac. |

Caps Lock uses macOS's per-keyboard modifier preferences, not an app that monitors keystrokes. Connect the keyboard before running; rerun for newly connected keyboards. The Bluetooth Logitech MX Master 3's keyboard interface is ignored. If a keyboard isn't detected or has a conflicting custom mapping, use **System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys** to set it without changing your other mappings.

## Check an existing Mac

```sh
./bootstrap.sh --doctor
```

Doctor checks the login shell and managed zsh files, installed dev tools and apps, saved Rectangle shortcuts, keyboard repeat, pointer speeds, and the saved Caps Lock mappings for detected keyboards. It reads local state only: no installs, network calls, app launches, or changes to preferences. It exits `0` if the checked settings match and `1` if it reports anything to review. A manually configured Mac can work fine even if its settings differ from the bootstrap. Doctor does not check for available updates or verify live key behavior or Rectangle's Accessibility permission.

To test the script itself without changing your setup:

```sh
/bin/bash tests/smoke.sh
```

The smoke test uses a temporary home and a temporary Rectangle preference file. It doesn't install apps or change your input settings.
