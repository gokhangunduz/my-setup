# my-setup

My one-command bootstrap for a fresh macOS machine. Paste a single line into the
terminal of a brand-new Mac and walk away — Homebrew, my CLI tools, my apps, and
my zsh setup all install themselves with a live, state-aware progress view.

## Quick start

Open Terminal on a fresh Mac and run:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/gokhangunduz/my-setup/main/install.sh)"
```

That's it. The script shows each step as it goes:

```
Applications
  ✓  google-chrome
  ✓  visual-studio-code
  ⊘  figma (already installed)
  ⠹  docker-desktop
  ...

Summary   ✓ 18 installed   ⊘ 2 skipped   ✗ 0 failed
```

## What it installs

| Category | Items |
| --- | --- |
| **Package manager** | Homebrew (with PATH wired into `~/.zprofile`) |
| **CLI tools** | git (+ global config), node, python, mas, MongoDB Community (via the `mongodb/brew` tap) |
| **Apps** | Google Chrome, Docker Desktop, VS Code, Postman, MongoDB Compass, Figma, Logitech Options+, BetterDisplay, ChatGPT, Google Gemini, Claude, Claude Code, Codex, TeamViewer, NVIDIA GeForce NOW |
| **Shell** | Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting, Powerlevel10k |
| **macOS settings** | Dark mode, Dock, Cmd+" window shortcut, firewall, battery/energy, local hostname |
| **App Store** | Xcode, WhatsApp, Apple Developer — installed from the App Store via `mas` |
| **macOS updates** | Starts a background `softwareupdate` download (no waiting, no restart) |

To change the list, edit the `TAPS`, `FORMULAE`, `CASKS`, and `MAS_APPS` arrays
at the top of [`install.sh`](install.sh) — they're the single source of truth.

### macOS settings

Applies these with `defaults write` (no sudo, no permission prompts), in
`setup_macos_settings`:

- **Dark mode** — dark interface + dark app icons (`AppleIconAppearanceTheme`,
  macOS 26 Tahoe).
- **Dock** — size and magnification (`tilesize` / `largesize`, eyeballed from a
  screenshot; tweak the numbers). Applied live via `killall Dock`.
- **Keyboard** — `Cmd+"` set to *Move focus to next window*, so it cycles the
  windows of the active app (symbolic hotkey 27; default is `Cmd+\``).
- **Firewall** — turned on via `socketfilterfw` (left alone if already on).
- **Battery/energy** — dim on battery, never auto-sleep on AC, wake for network
  only on power adapter (`pmset` `lessbright` / `sleep` / `womp`).
- **Local hostname** — set to `gg.local` (`scutil --set LocalHostName`).

Dark mode and the keyboard shortcut take effect at your **next login**; the Dock
updates immediately.

> Not automated (no supported CLI on macOS 26 — do these in the GUI): the
> wallpaper (built-in dynamic wallpapers have no scriptable API), **iCloud
> Photos** (tied to your Apple Account), and the **"Optimize video streaming on
> battery"** toggle. Screen resolution also isn't changed automatically — it
> needs a third-party tool and the right scaled mode per Mac model.

### Mac App Store apps

Xcode, WhatsApp, and Apple Developer are installed straight from the App Store
with [`mas`](https://github.com/mas-cli/mas) (installed via Homebrew in the CLI
tools step) — the apps themselves come from the App Store, not Homebrew. The
catch: `mas` can't sign in for you, so you must already be **signed
into the App Store app**. If you're not, those installs fail fast with a note to
sign in and re-run (everything else still completes). Already-installed apps are
skipped, and Xcode is several GB so that download can take a while.

### macOS software updates

The last step **kicks off** a macOS system-update download in the background
(`softwareupdate --download --all`, detached) and moves on — it never makes you
wait, never installs, and never restarts on its own. The download keeps running
after the script ends. When you're ready, install with `sudo softwareupdate -i -a`
or **System Settings ▸ General ▸ Software Update** (on Apple Silicon, system
updates that need a restart are best done from the GUI).

## Why this exists (and what's different)

This started as a plain `&&`-chained gist. It kept breaking halfway through. The
rewrite fixes the real culprits:

- **Oh My Zsh no longer hijacks the run.** Its installer normally ends by
  launching a new zsh (`exec zsh`), which replaced the running process and
  silently killed every step after it. It now runs with `--unattended`, so the
  script keeps going.
- **One failure no longer stops everything.** Each step runs independently. A
  missing cask or a hiccup is caught, reported at the end with its log, and the
  rest still installs.
- **One password prompt, then fully unattended.** sudo is asked **once** at the
  start; the script then drops a temporary passwordless-sudo rule in
  `/etc/sudoers.d/my-setup` and removes it on exit (even on Ctrl-C). Nothing else
  ever prompts — not Homebrew, not casks whose installer needs root (e.g.
  `logi-options+`, which used to hang on a hidden prompt), not `softwareupdate`.
  Oh My Zsh runs `--unattended`, so it never touches sudo or `chsh`.
- **Safe to re-run — and it updates.** Already-installed formulae/casks aren't
  just skipped: the script checks `brew outdated` and **upgrades** anything that
  has a newer version (shown as `(update)`), leaving current ones as `up to date`.
  Re-running doubles as your update command.
- **No more `source ~/.zshrc` from bash.** It just tells you to open a new
  terminal; `.zshrc` edits are idempotent (set, not append).
- **Apple Silicon & Intel.** The Homebrew prefix is detected automatically.

## Customizing

No flags, no environment variables — the script just runs. To change anything,
edit the lists at the top of [`install.sh`](install.sh): `FORMULAE`, `CASKS`,
`MAS_APPS`, the git identity, or the `apply_default` lines in
`setup_macos_settings`. That file is the single source of truth.

## Running it manually

If you'd rather inspect before running (recommended for any `curl | bash`):

```bash
git clone https://github.com/gokhangunduz/my-setup.git
cd my-setup
less install.sh   # read it first
./install.sh
```

## After it finishes

1. Open a new terminal (or `exec zsh`) to load the new shell.
2. Powerlevel10k's setup wizard starts on first launch — or run `p10k configure`.
3. Launch Docker Desktop once to complete its first-run setup.

## License

[MIT](LICENSE)
