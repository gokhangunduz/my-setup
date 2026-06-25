# my-setup

My one-command bootstrap for a fresh macOS machine. Paste a single line into the
terminal of a brand-new Mac and walk away — Homebrew, my CLI tools, my apps, and
my zsh setup all install themselves with a live, state-aware progress view.

## Quick start

Open Terminal on a fresh Mac and run:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/gokhangunduz/my-setup/main/install.sh)"
```

That's it. It clears the screen and runs as a full-screen, app-like view with
every step expanded so you always see what's done and what's coming:

```
  ✓ ④ 📦  Casks   17/17
      ✓  google-chrome
      ⊘  visual-studio-code             skipped
      ✓  webstorm
      ...
  ✓ ⑧ 🔄  macOS Updates   2/2
      ✓  Command Line Tools             started
      ⊘  macOS                          skipped

  100%  43/43 tasks

  ❖  my-setup  · done in 6m12s
  ✓ 24 installed   ↑ 3 updated   ⊘ 16 skipped   ✗ 0 failed
```

Each item shows its own state — `✓` installed, `↑` updated, `⊘` skipped (already
current), `✗` failed. The view stays put when it's done; the cursor is yours again.

## What it installs

| Category | Items |
| --- | --- |
| **Homebrew** | Installed (or updated) as its own step, with PATH wired into `~/.zprofile` |
| **Git** | git itself, then a global config (name/email, default branch, `pull.rebase false`) |
| **Formulae** | node, python, postgresql, sqlite, MongoDB Community (via the `mongodb/brew` tap), gh, hcloud, awscli, mas |
| **Casks** | Google Chrome, VS Code, WebStorm, Docker Desktop, Postman, MongoDB Compass, pgAdmin 4, Figma, ChatGPT, Google Gemini, Claude, Claude Code, Codex, Logitech Options+, BetterDisplay, TeamViewer, NVIDIA GeForce NOW |
| **Shell** | [antidote](https://antidote.sh) plugin manager driving `~/.zsh_plugins.txt`: Powerlevel10k, zsh-autosuggestions, zsh-syntax-highlighting, zsh-completions, and Oh My Zsh plugins (git, brew, macos, docker, gh, aws, npm, node, …) loaded via `ohmyzsh/ohmyzsh` |
| **macOS Settings** | Theme Mode (dark), App Icons, Dock, Shortcuts (`Cmd+"`), Firewall, Battery, Hostname |
| **Mac App Store** | Xcode, WhatsApp, Apple Developer — installed from the App Store via `mas` |
| **macOS Updates** | Command Line Tools and the macOS system, checked separately; available updates download in the background (no waiting, no restart) |

To change the list, edit the `TAPS`, `FORMULAE`, `CASKS`, and `MAS_APPS` arrays
at the top of [`install.sh`](install.sh) — they're the single source of truth.

### macOS Settings

Each setting is its own step, and every step checks the current state first — if
it's already what you want, it shows `⊘ skipped` instead of reapplying:

- **Theme Mode** — dark interface (`AppleInterfaceStyle`).
- **App Icons** — dark app icons (`AppleIconAppearanceTheme`, macOS 26 Tahoe).
- **Dock** — size and magnification (`tilesize` / `largesize`). Applied live via
  `killall Dock`.
- **Shortcuts** — `Cmd+"` set to *Move focus to next window*, so it cycles the
  windows of the active app (symbolic hotkey 27; default is `Cmd+\``).
- **Firewall** — turned on via `socketfilterfw` (left alone if already on).
- **Battery** — dim on battery, never auto-sleep on AC, wake for network only on
  power adapter (`pmset` `lessbright` / `sleep` / `womp`).
- **Hostname** — local hostname set to `gg.local` (`scutil --set LocalHostName`).

Theme Mode and the keyboard shortcut take effect at your **next login**; the Dock
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

The last step runs `softwareupdate -l` **once** and splits the result into two
separate checks — **Command Line Tools** and **macOS** — so you can see each one's
state on its own row. Whatever is available is **downloaded in the background**
(detached) and the script moves on — it never makes you wait, never installs, and
never restarts on its own. If nothing is pending, the row shows `⊘ skipped`. The
download keeps running after the script ends; install when you're ready with
`sudo softwareupdate -i -a` or **System Settings ▸ General ▸ Software Update** (on
Apple Silicon, system updates that need a restart are best done from the GUI).

## Why this exists (and what's different)

This started as a plain `&&`-chained gist. It kept breaking halfway through. The
rewrite fixes the real culprits:

- **Zsh plugins are managed by [antidote](https://antidote.sh), not Oh My Zsh's
  installer.** The OMZ installer used to end by launching a new zsh (`exec zsh`),
  which replaced the running process and silently killed every step after it.
  There's no OMZ install step anymore: antidote (a Homebrew formula) clones and
  loads everything — including the Oh My Zsh plugins — from `~/.zsh_plugins.txt`
  on first shell start. Nothing hijacks the run.
- **One failure no longer stops everything.** Each step runs independently. A
  missing cask or a hiccup is caught, reported at the end with its log, and the
  rest still installs.
- **One password prompt, then fully unattended.** sudo is asked **once** at the
  start; the script then drops a temporary passwordless-sudo rule in
  `/etc/sudoers.d/my-setup` and removes it on exit (even on Ctrl-C). Nothing else
  ever prompts — not Homebrew, not casks whose installer needs root (e.g.
  `logi-options+`, which used to hang on a hidden prompt), not `softwareupdate`.
- **Safe to re-run — and it updates.** Already-installed formulae/casks aren't
  just skipped: the script checks `brew outdated` and **upgrades** anything that
  has a newer version (shown as `↑`), leaving current ones as `⊘ skipped`.
  Re-running doubles as your update command.
- **`.zshrc` is edited safely.** my-setup writes only a fenced block
  (`# my-setup antidote begin … end`); your own lines are left untouched, and the
  block is regenerated only when it changes (otherwise the step shows `⊘ skipped`).
- **Apple Silicon & Intel.** The Homebrew prefix is detected automatically.

## Customizing

No flags, no environment variables — the script just runs. To change anything,
edit the lists at the top of [`install.sh`](install.sh): `TAPS`, `FORMULAE`,
`CASKS`, `MAS_APPS`, the git identity, or the `_*_prefs` functions for the macOS
settings. That file is the single source of truth.

## Running it manually

If you'd rather inspect before running (recommended for any `curl | bash`):

```bash
git clone https://github.com/gokhangunduz/my-setup.git
cd my-setup
less install.sh   # read it first
./install.sh
```

## After it finishes

1. Open a new terminal. The **first** start runs a little long — antidote clones
   every plugin (Oh My Zsh, Powerlevel10k, the zsh-users plugins) once; later
   starts are fast. Update plugins anytime with `antidote update`.
2. Powerlevel10k's setup wizard starts on first launch — or run `p10k configure`.
3. Launch Docker Desktop once to complete its first-run setup.

## License

[MIT](LICENSE)
