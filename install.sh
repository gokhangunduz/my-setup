#!/usr/bin/env bash
#
# my-setup · fresh macOS bootstrap
# https://github.com/gokhangunduz/my-setup
#
# Run on a brand-new Mac with a single command:
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/gokhangunduz/my-setup/main/install.sh)"
#
# Safe to re-run: every step checks its state first and skips what's already done.
# No flags, no environment variables — it just runs. Edit the lists below to
# change what gets installed.

set -uo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# What to install — edit these lists to taste.
# ─────────────────────────────────────────────────────────────────────────────

# Command-line tools (Homebrew formulae). `git` is handled in its own section.
FORMULAE=(
  node
  mas
)

# Applications (Homebrew casks).
CASKS=(
  google-chrome
  docker-desktop
  visual-studio-code
  postman
  figma
  logi-options+
  betterdisplay
  chatgpt
  google-gemini
  claude
  claude-code
  codex-app
  teamviewer
  nvidia-geforce-now
)

# Mac App Store apps, installed with `mas`: "app-id|name". These come straight
# from the App Store (not Homebrew). `mas` can't sign in for you, so you must
# already be signed into the App Store app. Xcode is several GB — expect a wait.
MAS_APPS=(
  "497799835|Xcode"
  "310633997|WhatsApp"
  "640199958|Apple Developer"
)

# Oh My Zsh plugins / theme: "label|destination|repo-url"
ZSH_PLUGINS=(
  "zsh-autosuggestions|plugins/zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions"
  "zsh-syntax-highlighting|plugins/zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting"
  "powerlevel10k|themes/powerlevel10k|https://github.com/romkatv/powerlevel10k"
)

# Git identity.
GIT_NAME="gokhangunduz"
GIT_EMAIL="me@gokhangunduz.dev"

# Final .zshrc settings.
ZSH_THEME_VALUE="powerlevel10k/powerlevel10k"
ZSH_PLUGINS_VALUE="git zsh-autosuggestions zsh-syntax-highlighting"

# ─────────────────────────────────────────────────────────────────────────────
# Internals — you usually don't need to touch anything below here.
# ─────────────────────────────────────────────────────────────────────────────

DONE=0
SKIPPED=0
FAILED=0
FAILED_ITEMS=""
SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
ERR_LOG="$(mktemp -t mysetup-errors 2>/dev/null || echo /tmp/mysetup-errors.$$)"
SUDO_KEEPALIVE_PID=""
SUDO_PRIMED=0
SUDOERS_FILE="/etc/sudoers.d/my-setup"
SUDOERS_INSTALLED=0
OUTDATED_FORMULAE=""
OUTDATED_CASKS=""

# Colors (auto-disabled when output isn't a terminal).
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'
  RESET=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
fi

# Carriage-return + clear-to-end-of-line: only meaningful on a live terminal,
# where they overwrite the spinner. Blank elsewhere so logs stay clean.
if [ -t 1 ]; then CR=$'\r'; CLR=$'\033[K'; else CR=""; CLR=""; fi

cleanup() {
  [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
  # Revoke the temporary passwordless-sudo rule (see prime_sudo). This must always
  # run, even on Ctrl-C, so we never leave the machine with an open sudo hole.
  [ "$SUDOERS_INSTALLED" = "1" ] && sudo rm -f "$SUDOERS_FILE" 2>/dev/null
  # Drop any cached sudo credential too.
  [ "$SUDO_PRIMED" = "1" ] && sudo -k 2>/dev/null
  [ -t 1 ] && command -v tput >/dev/null 2>&1 && tput cnorm 2>/dev/null
  rm -f "$ERR_LOG" 2>/dev/null
}
trap cleanup EXIT INT TERM

banner() {
  printf '\n%s%s' "$CYAN" "$BOLD"
  printf '   ┌──────────────────────────────────────────────┐\n'
  printf '   │   my-setup · fresh macOS bootstrap             │\n'
  printf '   └──────────────────────────────────────────────┘'
  printf '%s\n' "$RESET"
  printf '%s   github.com/gokhangunduz/my-setup%s\n' "$DIM" "$RESET"
}

section() {
  printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET"
}

info() { printf '%s  %s%s\n' "$DIM" "$1" "$RESET"; }

skip() {
  printf '  %s⊘%s  %s %s(already installed)%s\n' "$DIM" "$RESET" "$1" "$DIM" "$RESET"
  SKIPPED=$((SKIPPED + 1))
}

uptodate() {
  printf '  %s⊘%s  %s %s(up to date)%s\n' "$DIM" "$RESET" "$1" "$DIM" "$RESET"
  SKIPPED=$((SKIPPED + 1))
}

# apply_default <label> <defaults-write-args...> — apply a `defaults write`
# preference and report ✓ / ✗. Used for the macOS settings section.
apply_default() {
  local label="$1"; shift
  if defaults write "$@" 2>/dev/null; then
    printf '  %s✓%s  %s\n' "$GREEN" "$RESET" "$label"
    DONE=$((DONE + 1))
  else
    printf '  %s✗%s  %s\n' "$RED" "$RESET" "$label"
    FAILED=$((FAILED + 1)); FAILED_ITEMS="${FAILED_ITEMS} $label"
  fi
}

# _run <label> <command...> — run a command with a live spinner, capture output,
# and report ✓ / ✗. Never aborts the script; failures are collected for the end.
_run() {
  local label="$1"; shift
  local logf; logf="$(mktemp -t mysetup 2>/dev/null || echo "/tmp/mysetup.$$.$RANDOM")"

  "$@" >"$logf" 2>&1 &
  local pid=$!

  if [ -t 1 ]; then
    command -v tput >/dev/null 2>&1 && tput civis 2>/dev/null
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
      printf '\r  %s%s%s  %s\033[K' "$CYAN" "${SPINNER[i % ${#SPINNER[@]}]}" "$RESET" "$label"
      i=$((i + 1))
      sleep 0.08
    done
    command -v tput >/dev/null 2>&1 && tput cnorm 2>/dev/null
  fi

  wait "$pid"; local rc=$?

  if [ "$rc" -eq 0 ]; then
    printf '%s  %s✓%s  %s%s\n' "$CR" "$GREEN" "$RESET" "$label" "$CLR"
    DONE=$((DONE + 1))
  else
    printf '%s  %s✗%s  %s %s(failed)%s%s\n' "$CR" "$RED" "$RESET" "$label" "$DIM" "$RESET" "$CLR"
    FAILED=$((FAILED + 1))
    FAILED_ITEMS="${FAILED_ITEMS} ${label}"
    { printf '\n=== %s ===\n' "$label"; cat "$logf"; } >>"$ERR_LOG"
  fi

  rm -f "$logf"
  return 0
}

# ── Preflight ────────────────────────────────────────────────────────────────

preflight() {
  if [ "$(uname -s)" != "Darwin" ]; then
    printf '%sThis installer is for macOS only.%s\n' "$RED" "$RESET"
    exit 1
  fi
  if [ "$(uname -m)" = "arm64" ]; then
    BREW_PREFIX="/opt/homebrew"
  else
    BREW_PREFIX="/usr/local"
  fi
}

# ── Homebrew ─────────────────────────────────────────────────────────────────

ensure_homebrew() {
  section "Homebrew"
  if command -v brew >/dev/null 2>&1; then
    BREW_PREFIX="$(brew --prefix)"
    skip "Homebrew"
  else
    info "Installing Homebrew..."
    # NONINTERACTIVE=1 is Homebrew's own required flag to skip its "Press RETURN"
    # prompt — it's hardcoded here, not something you set. Nothing else uses env.
    if NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
      printf '  %s✓%s  Homebrew\n' "$GREEN" "$RESET"
      DONE=$((DONE + 1))
    else
      printf '  %s✗%s  Homebrew — cannot continue without it.\n' "$RED" "$RESET"
      exit 1
    fi
  fi

  # Make brew available in this script and in future login shells.
  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
  local line='eval "$('"$BREW_PREFIX"'/bin/brew shellenv)"'
  if ! grep -qsF "$line" "$HOME/.zprofile" 2>/dev/null; then
    printf '\n%s\n' "$line" >>"$HOME/.zprofile"
  fi

  _run "Updating Homebrew" brew update

  # Snapshot what's outdated so already-installed items get upgraded, not skipped.
  OUTDATED_FORMULAE="$(brew outdated --formula --quiet 2>/dev/null)"
  OUTDATED_CASKS="$(brew outdated --cask --quiet 2>/dev/null)"
}

# ── Git ──────────────────────────────────────────────────────────────────────

_configure_git() {
  brew list --formula --versions git >/dev/null 2>&1 || brew install git || return 1
  git config --global user.name "$GIT_NAME"
  git config --global user.email "$GIT_EMAIL"
  git config --global init.defaultBranch main
  git config --global color.ui true
  git config --global pull.rebase false
}

setup_git() {
  section "Git"
  _run "git (install + global config)" _configure_git
}

# ── Formulae & casks ─────────────────────────────────────────────────────────

install_formula() {
  local name="$1"
  if ! brew list --formula --versions "$name" >/dev/null 2>&1; then
    _run "$name" brew install "$name"
  elif printf '%s\n' "$OUTDATED_FORMULAE" | grep -qxF "$name"; then
    _run "$name (update)" brew upgrade --formula "$name"
  else
    uptodate "$name"
  fi
}

install_cask() {
  local name="$1"
  if ! brew list --cask --versions "$name" >/dev/null 2>&1; then
    _run "$name" brew install --cask "$name"
  elif printf '%s\n' "$OUTDATED_CASKS" | grep -qxF "$name"; then
    _run "$name (update)" brew upgrade --cask "$name"
  else
    uptodate "$name"
  fi
}

setup_formulae() {
  section "Command-line tools"
  local f
  for f in "${FORMULAE[@]}"; do
    install_formula "$f"
  done
}

# Ask for the password ONCE, then install a temporary passwordless-sudo rule for
# this user (/etc/sudoers.d/my-setup) so nothing — Homebrew, casks like
# logi-options+ whose installer needs root, softwareupdate — ever stops to prompt
# again. The rule is revoked automatically when the script exits (see cleanup),
# including on Ctrl-C. A timestamp keep-alive is the fallback if we can't write it.
prime_sudo() {
  section "Administrator access"
  printf '  You will be asked for your macOS password %s%sonce%s%s now — after that the\n' \
    "$BOLD" "$YELLOW" "$RESET" "$DIM"
  printf '  whole run is unattended (no more prompts).%s\n' "$RESET"
  if ! sudo -v; then
    printf '\n  %sCould not obtain administrator access — aborting.%s\n' "$RED" "$RESET"
    printf '  %sMake sure your account is an Administrator and try again.%s\n' "$DIM" "$RESET"
    exit 1
  fi
  SUDO_PRIMED=1

  # Try the passwordless rule (validated before it counts, so a bad write can't
  # lock you out of sudo). If anything fails, fall back to a timestamp keep-alive.
  if printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$(id -un)" | sudo tee "$SUDOERS_FILE" >/dev/null 2>&1 \
     && sudo chmod 440 "$SUDOERS_FILE" 2>/dev/null \
     && sudo visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
    SUDOERS_INSTALLED=1
    info "Granted for this run — revoked automatically when it finishes."
  else
    sudo rm -f "$SUDOERS_FILE" 2>/dev/null
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
  fi
}

setup_casks() {
  section "Applications"
  local c
  for c in "${CASKS[@]}"; do
    install_cask "$c"
  done
}

# ── macOS settings ───────────────────────────────────────────────────────────

# Apply macOS preferences via `defaults write`. All permission-free (no sudo, no
# TCC prompts). Appearance changes take effect at the next login or for newly
# launched apps. Add more `apply_default` lines here as you like.
setup_macos_settings() {
  section "macOS settings"

  # Appearance: dark interface + dark app icons (macOS 26 Tahoe).
  apply_default "Dark interface"  -g AppleInterfaceStyle      -string Dark
  apply_default "Dark app icons"  -g AppleIconAppearanceTheme -string RegularDark

  # Dock: size + magnification (values eyeballed from the reference screenshot;
  # tilesize/largesize both run 16–128, tweak to taste).
  apply_default "Dock size"          com.apple.dock tilesize      -int 64
  apply_default "Dock magnification" com.apple.dock magnification -bool true
  apply_default "Dock zoom size"     com.apple.dock largesize     -int 92
  killall Dock 2>/dev/null || true

  # Keyboard: Cmd+" cycles the windows of the active app (Alt-Tab-style, but for
  # one app's windows). This is "Move focus to next window" — symbolic hotkey 27,
  # default Cmd+`. parameters = (char ", key ', Cmd+Shift).
  if defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 27 \
       '{enabled=1;value={parameters=(34,39,1179648);type=standard;};}' 2>/dev/null; then
    printf '  %s✓%s  Cmd+" switches windows in the active app\n' "$GREEN" "$RESET"
    DONE=$((DONE + 1))
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
  else
    printf '  %s✗%s  Cmd+" window-switch shortcut\n' "$RED" "$RESET"
    FAILED=$((FAILED + 1)); FAILED_ITEMS="${FAILED_ITEMS} kbd-shortcut"
  fi

  # Wallpaper: "Radial Blue" is a dynamic .madesktop, which macOS 26 records in an
  # opaque binary store — there's no reliable unattended way to set it. So open
  # the Wallpaper pane and let you pick it with one click.
  open "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension" 2>/dev/null \
    && printf '  %s↗%s  Wallpaper settings opened — choose %sRadial Blue%s\n' "$CYAN" "$RESET" "$BOLD" "$RESET"

  info "Dark mode + keyboard shortcut apply at your next login; the Dock is live now."
}

# ── Mac App Store ────────────────────────────────────────────────────────────

# Install Mac App Store apps with `mas`. They come from the App Store, not
# Homebrew. `mas` can't sign in for you on modern macOS, so you must already be
# signed into the App Store app; if not, the installs below fail fast with a
# clear message and the rest of the setup carries on.
setup_appstore() {
  [ "${#MAS_APPS[@]}" -eq 0 ] && return
  section "Mac App Store"

  # mas (the App Store CLI) is installed as a formula in the Command-line tools
  # step above; bail out gracefully if it somehow isn't available.
  command -v mas >/dev/null 2>&1 || { info "mas unavailable — skipping App Store apps."; return; }

  # Don't hard-gate on the sign-in check (it's unreliable across macOS versions);
  # just warn, then let each install succeed or fail on its own.
  if ! mas account >/dev/null 2>&1; then
    info "Couldn't confirm App Store sign-in. If the installs below fail, open the"
    info "App Store app, sign in, then re-run."
  fi

  local installed entry id name
  installed="$(mas list 2>/dev/null)"
  for entry in "${MAS_APPS[@]}"; do
    id="${entry%%|*}"
    name="${entry##*|}"
    if printf '%s\n' "$installed" | grep -q "^$id "; then
      skip "$name"
      continue
    fi
    # Foreground so big downloads (Xcode is several GB) show their own progress.
    info "Installing $name from the App Store (this can be large)..."
    if mas install "$id"; then
      printf '  %s✓%s  %s\n' "$GREEN" "$RESET" "$name"
      DONE=$((DONE + 1))
    else
      printf '  %s✗%s  %s %s(sign in to the App Store, then re-run)%s\n' "$RED" "$RESET" "$name" "$DIM" "$RESET"
      FAILED=$((FAILED + 1)); FAILED_ITEMS="${FAILED_ITEMS} $name"
    fi
  done
}

# ── Zsh: Oh My Zsh + plugins + Powerlevel10k ─────────────────────────────────

_install_omz() {
  local script; script="$(mktemp -t omz-install 2>/dev/null || echo "/tmp/omz.$$")"
  curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$script" || return 1
  # --unattended already sets RUNZSH=no and CHSH=no, so the installer won't launch
  # zsh or change the login shell mid-run — the exact bug that cut the old script
  # short. (No env vars needed.)
  sh "$script" --unattended
  local rc=$?
  rm -f "$script"
  return $rc
}

_configure_zshrc() {
  local rc="$HOME/.zshrc"
  [ -f "$rc" ] || touch "$rc"

  if grep -q '^ZSH_THEME=' "$rc"; then
    sed -i '' "s|^ZSH_THEME=.*|ZSH_THEME=\"$ZSH_THEME_VALUE\"|" "$rc"
  else
    printf '\nZSH_THEME="%s"\n' "$ZSH_THEME_VALUE" >>"$rc"
  fi

  if grep -q '^plugins=' "$rc"; then
    sed -i '' "s|^plugins=.*|plugins=($ZSH_PLUGINS_VALUE)|" "$rc"
  else
    printf '\nplugins=(%s)\n' "$ZSH_PLUGINS_VALUE" >>"$rc"
  fi
}

setup_zsh() {
  section "Shell (Oh My Zsh + Powerlevel10k)"

  if [ -d "$HOME/.oh-my-zsh" ]; then
    skip "Oh My Zsh"
  else
    _run "Oh My Zsh" _install_omz
  fi

  local custom="$HOME/.oh-my-zsh/custom"
  local entry label dest url
  for entry in "${ZSH_PLUGINS[@]}"; do
    label="${entry%%|*}"
    dest="${entry#*|}"; dest="${dest%%|*}"
    url="${entry##*|}"
    if [ -d "$custom/$dest" ]; then
      skip "$label"
    else
      _run "$label" git clone --depth=1 "$url" "$custom/$dest"
    fi
  done

  _run ".zshrc (theme + plugins)" _configure_zshrc
}

# ── macOS software updates ───────────────────────────────────────────────────

# Kick off the macOS system-update download and move on — we do NOT wait for it.
# `softwareupdate --download --all` checks for and downloads any updates; we run
# it detached (nohup, in the background) so the download keeps going after the
# script ends without ever blocking the run. Installing/restarting is left to you.
setup_macos_update() {
  section "macOS updates"
  nohup sudo softwareupdate --download --all >/dev/null 2>&1 &
  printf '  %s↗%s  Checking + downloading any updates in the background (not waiting).\n' "$CYAN" "$RESET"
  printf '  %sInstall when you are ready: %ssudo softwareupdate -i -a%s%s  (or System Settings ▸ Software Update).%s\n' \
    "$DIM" "$BOLD" "$RESET" "$DIM" "$RESET"
}

# ── Summary ──────────────────────────────────────────────────────────────────

summary() {
  printf '\n%s────────────────────────────────────────────────%s\n' "$DIM" "$RESET"
  printf '%sSummary%s   %s✓ %d installed%s   %s⊘ %d skipped%s   %s✗ %d failed%s\n' \
    "$BOLD" "$RESET" \
    "$GREEN" "$DONE" "$RESET" \
    "$DIM" "$SKIPPED" "$RESET" \
    "$RED" "$FAILED" "$RESET"

  if [ "$FAILED" -gt 0 ]; then
    printf '\n%sFailed:%s%s\n' "$YELLOW" "$FAILED_ITEMS" "$RESET"
    printf '%sDetails:%s\n' "$DIM" "$RESET"
    sed 's/^/    /' "$ERR_LOG"
    printf '\n%sRe-run the command to retry — finished steps are skipped automatically.%s\n' "$DIM" "$RESET"
  fi

  section "Next steps"
  printf '  1. Open a new terminal (or run: %sexec zsh%s) to load your new shell.\n' "$BOLD" "$RESET"
  printf '  2. Powerlevel10k starts its setup wizard on first launch (or run: %sp10k configure%s).\n' "$BOLD" "$RESET"
  printf '  3. Your apps are in %s/Applications%s — launch Docker once to finish its setup.\n' "$BOLD" "$RESET"
  printf '\n%sDone. Enjoy your fresh Mac.%s\n\n' "$GREEN" "$RESET"
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  banner
  preflight
  prime_sudo      # one password prompt up front; everything after is unattended
  ensure_homebrew
  setup_git
  setup_formulae
  setup_casks
  setup_zsh
  setup_macos_settings
  setup_appstore
  setup_macos_update
  summary
}

main "$@"
