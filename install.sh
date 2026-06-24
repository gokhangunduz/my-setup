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

# No `set -e` (a failed step must never abort the run) and no `set -u` (an
# unexpected unset/empty variable must never crash it either). Each step handles
# its own success/failure and the script always moves on to the next one.
set -o pipefail

# ─────────────────────────────────────────────────────────────────────────────
# What to install — edit these lists to taste.
# ─────────────────────────────────────────────────────────────────────────────

# Extra Homebrew taps needed by some formulae below (tapped before installing).
TAPS=(
  mongodb/brew
)

# Command-line tools (Homebrew formulae). `git` is handled in its own section.
# mongodb-community is the latest MongoDB Community server (from mongodb/brew).
FORMULAE=(
  node
  python
  mas
  mongodb-community
)

# Applications (Homebrew casks).
CASKS=(
  google-chrome
  docker-desktop
  visual-studio-code
  postman
  mongodb-compass
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
SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
ERR_LOG="$(mktemp -t mysetup-errors 2>/dev/null || echo /tmp/mysetup-errors.$$)"
SUDO_KEEPALIVE_PID=""
SUDO_PRIMED=0
SUDOERS_FILE="/etc/sudoers.d/my-setup"
SUDOERS_INSTALLED=0
OUTDATED_FORMULAE=""
OUTDATED_CASKS=""

STEP=0           # current section number
TOTAL_STEPS=9    # keep in sync with the section() calls in main()
RUN_OK=0         # set by _run: 1 if the last command succeeded
STEP_TIMEOUT=1200  # seconds: kill any single _run step that hangs longer, then continue
# Recap buckets — newline-separated names (so entries like "Apple Developer" work)
RECAP_INSTALLED=""
RECAP_UPDATED=""
RECAP_SKIPPED=""
RECAP_FAILED=""

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
  printf '   ╭──────────────────────────────────────────────╮\n'
  printf '   │   my-setup · fresh macOS bootstrap             │\n'
  printf '   ╰──────────────────────────────────────────────╯'
  printf '%s\n' "$RESET"
  printf '%s   github.com/gokhangunduz/my-setup%s\n' "$DIM" "$RESET"
}

# Up-front overview of every step so you know what's coming, not just the step
# you're on. Keep the entries in sync with the section() calls in main().
show_plan() {
  local rule="  ${DIM}────────────────────────────────────────────────${RESET}"
  printf '\n  %sPlan%s  %s· %d steps%s\n%s\n' "$BOLD" "$RESET" "$DIM" "$TOTAL_STEPS" "$RESET" "$rule"
  local entries=(
    "🔑|Administrator access|one password, then unattended"
    "🍺|Homebrew|the package manager"
    "🔧|Git|install + global config"
    "💻|Command-line tools|${#FORMULAE[@]} tools"
    "📦|Applications|${#CASKS[@]} apps"
    "🐚|Shell|Oh My Zsh + Powerlevel10k"
    "🎨|macOS settings|dark, Dock, firewall, battery, hostname"
    "🛒|Mac App Store|${#MAS_APPS[@]} apps"
    "🔄|macOS updates|download in background"
  )
  local i=0 e icon rest title detail
  for e in "${entries[@]}"; do
    i=$((i + 1))
    icon="${e%%|*}"; rest="${e#*|}"; title="${rest%%|*}"; detail="${rest##*|}"
    printf '  %s%s%d%s %s  %s%-21s%s %s%s%s\n' \
      "$DIM" "$CYAN" "$i" "$RESET" "$icon" "$BOLD" "$title" "$RESET" "$DIM" "$detail" "$RESET"
  done
  printf '%s\n' "$rule"
}

# Format a whole number of seconds as "12s" or "1m 47s".
fmt_secs() {
  if [ "$1" -lt 60 ]; then printf '%ds' "$1"; else printf '%dm %02ds' $(("$1" / 60)) $(("$1" % 60)); fi
}

# Recap bookkeeping (newline-separated; safe for names with spaces).
rec_installed() { RECAP_INSTALLED="${RECAP_INSTALLED}"$'\n'"$1"; }
rec_updated()   { RECAP_UPDATED="${RECAP_UPDATED}"$'\n'"$1"; }
rec_skipped()   { RECAP_SKIPPED="${RECAP_SKIPPED}"$'\n'"$1"; }
note_fail()     { FAILED=$((FAILED + 1)); RECAP_FAILED="${RECAP_FAILED}"$'\n'"$1"; }

# section <title> <icon> [count] — numbered header with a category icon, plus a
# dim running tally of the work so far (the "live total").
section() {
  if [ "$STEP" -gt 0 ] && [ "$((DONE + SKIPPED + FAILED))" -gt 0 ]; then
    printf '   %s✓ %d   ⊘ %d   ✗ %d%s\n' "$DIM" "$DONE" "$SKIPPED" "$FAILED" "$RESET"
  fi
  STEP=$((STEP + 1))
  local suffix=""
  [ -n "${3:-}" ] && suffix="  ${DIM}· ${3}${RESET}"
  printf '\n%s[%d/%d]%s %s  %s%s%s%s%s\n' \
    "$DIM" "$STEP" "$TOTAL_STEPS" "$RESET" "$2" "$CYAN" "$BOLD" "$1" "$RESET" "$suffix"
}

info() { printf '%s  %s%s\n' "$DIM" "$1" "$RESET"; }

skip() {
  printf '  %s⊘%s  %s %s(already installed)%s\n' "$DIM" "$RESET" "$1" "$DIM" "$RESET"
  SKIPPED=$((SKIPPED + 1)); rec_skipped "$1"
}

uptodate() {
  printf '  %s⊘%s  %s %s(up to date)%s\n' "$DIM" "$RESET" "$1" "$DIM" "$RESET"
  SKIPPED=$((SKIPPED + 1)); rec_skipped "$1"
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
    note_fail "$label"
  fi
}

# apply_step <label> <command...> — run a settings command (often via sudo) and
# report ✓ / ✗. Like apply_default but for non-`defaults` tweaks.
apply_step() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  %s✓%s  %s\n' "$GREEN" "$RESET" "$label"
    DONE=$((DONE + 1))
  else
    printf '  %s✗%s  %s\n' "$RED" "$RESET" "$label"
    note_fail "$label"
  fi
}

# _run <label> <command...> — run a command with a live spinner, capture output,
# time it, and report ✓ (with elapsed time) / ✗. Sets RUN_OK to 1/0. Never aborts;
# failures are collected for the end recap.
_run() {
  local label="$1"; shift
  local logf; logf="$(mktemp -t mysetup 2>/dev/null || echo "/tmp/mysetup.$$.$RANDOM")"
  local t0=$SECONDS

  "$@" >"$logf" 2>&1 &
  local pid=$!

  # Poll until the step finishes (animating a spinner on a terminal). If it hangs
  # past STEP_TIMEOUT, terminate it so the run continues. The timeout lives inside
  # this loop — no background timer — so nothing is ever left running afterwards.
  [ -t 1 ] && command -v tput >/dev/null 2>&1 && tput civis 2>/dev/null
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$((SECONDS - t0))" -ge "$STEP_TIMEOUT" ]; then
      printf '\n[my-setup] step exceeded %ss — terminated so the run can continue\n' "$STEP_TIMEOUT" >>"$logf"
      kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null
      break
    fi
    if [ -t 1 ]; then
      printf '\r  %s%s%s  %s\033[K' "$CYAN" "${SPINNER[i % ${#SPINNER[@]}]}" "$RESET" "$label"
      i=$((i + 1)); sleep 0.08
    else
      sleep 1
    fi
  done
  [ -t 1 ] && command -v tput >/dev/null 2>&1 && tput cnorm 2>/dev/null

  { wait "$pid"; } 2>/dev/null; local rc=$?   # 2>/dev/null hides the "Terminated" note

  local dt=$((SECONDS - t0)) took=""
  [ "$dt" -ge 1 ] && took="$(fmt_secs "$dt")"

  if [ "$rc" -eq 0 ]; then
    printf '%s  %s✓%s  %-34s %s%s%s%s\n' "$CR" "$GREEN" "$RESET" "$label" "$DIM" "$took" "$RESET" "$CLR"
    DONE=$((DONE + 1)); RUN_OK=1
  else
    printf '%s  %s✗%s  %-34s %s(failed)%s%s\n' "$CR" "$RED" "$RESET" "$label" "$DIM" "$RESET" "$CLR"
    note_fail "$label"; RUN_OK=0
    { printf '\n=== %s ===\n' "$label"; cat "$logf"; } >>"$ERR_LOG"
  fi

  rm -f "$logf"
  return 0
}

# ── Live checklist (for the brew formula/cask lists) ─────────────────────────
# Renders the whole list up front as pending (○), then resolves each line in
# place — ⊘ up-to-date, spinner while installing/updating, then ✓/↑/✗ — so the
# full list and what's next are always visible. Falls back to plain sequential
# output when stdout isn't a terminal.

# Rewrite the line that is $1 rows above the cursor, then return to the bottom.
_line_set() { printf '\033[%dA\r\033[K%s\033[%dB\r' "$1" "$2" "$1"; }

# Decide what to do with one package: echoes install | update | uptodate.
_classify() {
  local kind="$1" name="$2" outdated
  brew list --"$kind" --versions "$name" >/dev/null 2>&1 || { echo install; return; }
  [ "$kind" = formula ] && outdated="$OUTDATED_FORMULAE" || outdated="$OUTDATED_CASKS"
  printf '%s\n' "$outdated" | grep -qxF "$name" && echo update || echo uptodate
}

# Run a command while animating a spinner on the line $1 rows above the cursor,
# with the same timeout/logging as _run. Finalizes that line with ✓ / ✗.
_cl_exec() {
  local up="$1" label="$2"; shift 2
  local logf; logf="$(mktemp -t mysetup 2>/dev/null || echo "/tmp/mysetup.$$.$RANDOM")"
  local t0=$SECONDS
  "$@" >"$logf" 2>&1 &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$((SECONDS - t0))" -ge "$STEP_TIMEOUT" ]; then
      printf '\n[my-setup] step exceeded %ss — terminated so the run can continue\n' "$STEP_TIMEOUT" >>"$logf"
      kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null; break
    fi
    _line_set "$up" "  ${CYAN}${SPINNER[i % ${#SPINNER[@]}]}${RESET}  ${label}"
    i=$((i + 1)); sleep 0.08
  done
  { wait "$pid"; } 2>/dev/null; local rc=$?
  local dt=$((SECONDS - t0)) took=""
  [ "$dt" -ge 1 ] && took="$(fmt_secs "$dt")"
  if [ "$rc" -eq 0 ]; then
    _line_set "$up" "  ${GREEN}✓${RESET}  ${label}$([ -n "$took" ] && printf '   %s%s%s' "$DIM" "$took" "$RESET")"
    DONE=$((DONE + 1)); RUN_OK=1
  else
    _line_set "$up" "  ${RED}✗${RESET}  ${label} ${DIM}(failed)${RESET}"
    note_fail "$label"; RUN_OK=0
    { printf '\n=== %s ===\n' "$label"; cat "$logf"; } >>"$ERR_LOG"
  fi
  rm -f "$logf"
}

# process_list <formula|cask> <name...> — install/update each, as a live checklist.
process_list() {
  local kind="$1"; shift
  local names=("$@")
  local n=$# nm act
  [ "$n" -eq 0 ] && return

  if [ ! -t 1 ]; then            # no terminal: plain sequential output
    for nm in "${names[@]}"; do
      act="$(_classify "$kind" "$nm")"
      case "$act" in
        uptodate) uptodate "$nm" ;;
        install)  if [ "$kind" = cask ]; then _run "$nm" brew install --cask "$nm"; else _run "$nm" brew install "$nm"; fi
                  [ "$RUN_OK" = 1 ] && rec_installed "$nm" ;;
        update)   _run "$nm (update)" brew upgrade --"$kind" "$nm"; [ "$RUN_OK" = 1 ] && rec_updated "$nm" ;;
      esac
    done
    return
  fi

  # terminal: render the whole list as pending, then resolve each line in place
  command -v tput >/dev/null 2>&1 && tput civis 2>/dev/null
  for nm in "${names[@]}"; do printf '  %s○%s  %s\n' "$DIM" "$RESET" "$nm"; done
  local k=0 up
  for nm in "${names[@]}"; do
    k=$((k + 1)); up=$((n - k + 1))
    act="$(_classify "$kind" "$nm")"
    case "$act" in
      uptodate)
        _line_set "$up" "  ${DIM}⊘${RESET}  ${nm} ${DIM}(up to date)${RESET}"
        SKIPPED=$((SKIPPED + 1)); rec_skipped "$nm" ;;
      install)
        if [ "$kind" = cask ]; then _cl_exec "$up" "$nm" brew install --cask "$nm"
        else _cl_exec "$up" "$nm" brew install "$nm"; fi
        [ "$RUN_OK" = 1 ] && rec_installed "$nm" ;;
      update)
        _cl_exec "$up" "$nm (update)" brew upgrade --"$kind" "$nm"
        [ "$RUN_OK" = 1 ] && rec_updated "$nm" ;;
    esac
  done
  command -v tput >/dev/null 2>&1 && tput cnorm 2>/dev/null
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
  section "Homebrew" "🍺"
  if command -v brew >/dev/null 2>&1; then
    BREW_PREFIX="$(brew --prefix)"
    skip "Homebrew"
  else
    info "Installing Homebrew..."
    # NONINTERACTIVE=1 is Homebrew's own required flag to skip its "Press RETURN"
    # prompt — it's hardcoded here, not something you set. Nothing else uses env.
    NONINTERACTIVE=1 /bin/bash -c \
      "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
    # Trust the actual result, not the installer's exit code (a failed curl would
    # otherwise look like success): continue only if the brew binary is really there.
    if [ -x "$BREW_PREFIX/bin/brew" ] || command -v brew >/dev/null 2>&1; then
      printf '  %s✓%s  Homebrew\n' "$GREEN" "$RESET"
      DONE=$((DONE + 1)); rec_installed "Homebrew"
    else
      printf '  %s✗%s  Homebrew — cannot continue without it (check your connection and re-run).\n' "$RED" "$RESET"
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
  section "Git" "🔧"
  _run "git (install + global config)" _configure_git
}

# ── Formulae & casks ─────────────────────────────────────────────────────────

setup_formulae() {
  section "Command-line tools" "💻" "${#FORMULAE[@]}"
  local t
  # Add any third-party taps first (e.g. mongodb/brew for mongodb-community) and
  # trust them — newer Homebrew refuses to load formulae from an untrusted tap.
  for t in "${TAPS[@]}"; do
    if brew tap 2>/dev/null | grep -qxF "$t"; then
      skip "tap $t"
    else
      _run "tap $t" brew tap "$t"
    fi
    brew trust --tap "$t" >/dev/null 2>&1 || true
  done
  process_list formula "${FORMULAE[@]}"
}

# Ask for the password ONCE, then install a temporary passwordless-sudo rule for
# this user (/etc/sudoers.d/my-setup) so nothing — Homebrew, casks like
# logi-options+ whose installer needs root, softwareupdate — ever stops to prompt
# again. The rule is revoked automatically when the script exits (see cleanup),
# including on Ctrl-C. A timestamp keep-alive is the fallback if we can't write it.
prime_sudo() {
  section "Administrator access" "🔑"
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
  section "Applications" "📦" "${#CASKS[@]}"
  process_list cask "${CASKS[@]}"
}

# ── macOS settings ───────────────────────────────────────────────────────────

# Apply macOS preferences via `defaults write`. All permission-free (no sudo, no
# TCC prompts). Appearance changes take effect at the next login or for newly
# launched apps. Add more `apply_default` lines here as you like.
setup_macos_settings() {
  section "macOS settings" "🎨"

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
  # one app's windows). This is "Move focus to next window" — symbolic hotkey 27.
  # parameters = (34 = the " character, 10 = its key code on this keyboard layout,
  # 1048576 = Cmd). Captured verbatim from System Settings after setting ⌘" by
  # hand, so it reproduces exactly; re-capture if your keyboard layout differs.
  if defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 27 \
       '{enabled=1;value={parameters=(34,10,1048576);type=standard;};}' 2>/dev/null; then
    printf '  %s✓%s  Cmd+" switches windows in the active app\n' "$GREEN" "$RESET"
    DONE=$((DONE + 1))
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
  else
    printf '  %s✗%s  Cmd+" window-switch shortcut\n' "$RED" "$RESET"
    note_fail "Cmd+\" shortcut"
  fi

  # Firewall: turn on, but leave it alone if it's already enabled.
  if /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q 'State = 1'; then
    printf '  %s⊘%s  Firewall %s(already on)%s\n' "$DIM" "$RESET" "$DIM" "$RESET"
    SKIPPED=$((SKIPPED + 1))
  else
    apply_step "Firewall on" sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
  fi

  # Battery / energy (matches the reference screenshot): dim on battery, never
  # auto-sleep on AC, and wake for network access only on power adapter.
  apply_step "Battery preferences" _battery_prefs

  # Local hostname → gg.local (scutil appends .local for Bonjour).
  apply_step "Local hostname (gg.local)" sudo scutil --set LocalHostName gg

  info "Dark mode + keyboard shortcut apply at your next login; the Dock is live now."
}

_battery_prefs() {
  sudo pmset -b lessbright 1 &&   # slightly dim the display on battery
  sudo pmset -c sleep 0 &&        # prevent auto-sleep on power adapter
  sudo pmset -c womp 1 &&         # wake for network access on power adapter
  sudo pmset -b womp 0            # ...but not on battery
}

# ── Mac App Store ────────────────────────────────────────────────────────────

# Install Mac App Store apps with `mas`. They come from the App Store, not
# Homebrew. `mas` can't sign in for you on modern macOS, so you must already be
# signed into the App Store app; if not, the installs below fail fast with a
# clear message and the rest of the setup carries on.
setup_appstore() {
  [ "${#MAS_APPS[@]}" -eq 0 ] && return
  section "Mac App Store" "🛒" "${#MAS_APPS[@]}"

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
      DONE=$((DONE + 1)); rec_installed "$name"
    else
      printf '  %s✗%s  %s %s(sign in to the App Store, then re-run)%s\n' "$RED" "$RESET" "$name" "$DIM" "$RESET"
      note_fail "$name"
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
  section "Shell (Oh My Zsh + Powerlevel10k)" "🐚"

  if [ -d "$HOME/.oh-my-zsh" ]; then
    skip "Oh My Zsh"
  else
    _run "Oh My Zsh" _install_omz; [ "$RUN_OK" = 1 ] && rec_installed "Oh My Zsh"
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
      _run "$label" git clone --depth=1 "$url" "$custom/$dest"; [ "$RUN_OK" = 1 ] && rec_installed "$label"
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
  section "macOS updates" "🔄"
  nohup sudo softwareupdate --download --all >/dev/null 2>&1 &
  printf '  %s↗%s  Checking + downloading any updates in the background (not waiting).\n' "$CYAN" "$RESET"
  printf '  %sInstall when you are ready: %ssudo softwareupdate -i -a%s%s  (or System Settings ▸ Software Update).%s\n' \
    "$DIM" "$BOLD" "$RESET" "$DIM" "$RESET"
}

# ── Summary ──────────────────────────────────────────────────────────────────

# Print one recap line: "Label (N)  a · b · c" from a newline-separated list.
_recap_bucket() {
  local label="$1" color="$2" names="$3"
  local n=0 joined="" line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    n=$((n + 1))
    if [ -n "$joined" ]; then joined="$joined · $line"; else joined="$line"; fi
  done <<EOF
$names
EOF
  [ -z "$joined" ] && joined="—"
  printf '  %s%-9s%s %s(%d)%s  %s\n' "$color" "$label" "$RESET" "$DIM" "$n" "$RESET" "$joined"
}

summary() {
  printf '\n%s────────────────────────────────────────────────%s\n' "$DIM" "$RESET"
  printf '%sSummary%s  %s✓ %d%s  %s⊘ %d%s  %s✗ %d%s   %s·%s  ⏱ %s\n' \
    "$BOLD" "$RESET" "$GREEN" "$DONE" "$RESET" "$DIM" "$SKIPPED" "$RESET" \
    "$RED" "$FAILED" "$RESET" "$DIM" "$RESET" "$(fmt_secs "$SECONDS")"

  printf '\n%sRecap%s\n' "$BOLD" "$RESET"
  _recap_bucket "Installed" "$GREEN" "$RECAP_INSTALLED"
  _recap_bucket "Updated"   "$CYAN"  "$RECAP_UPDATED"
  _recap_bucket "Skipped"   "$DIM"   "$RECAP_SKIPPED"
  _recap_bucket "Failed"    "$RED"   "$RECAP_FAILED"

  if [ "$FAILED" -gt 0 ]; then
    printf '\n%sFailure details:%s\n' "$YELLOW" "$RESET"
    sed 's/^/    /' "$ERR_LOG"
    printf '%sRe-run to retry — finished steps are skipped automatically.%s\n' "$DIM" "$RESET"
  fi

  printf '\n%sNext steps%s\n' "$BOLD" "$RESET"
  printf '  1. Open a new terminal (or run: %sexec zsh%s) to load your new shell.\n' "$BOLD" "$RESET"
  printf '  2. Powerlevel10k starts its setup wizard on first launch (or run: %sp10k configure%s).\n' "$BOLD" "$RESET"
  printf '  3. Your apps are in %s/Applications%s — launch Docker once to finish its setup.\n' "$BOLD" "$RESET"
  printf '  4. Start MongoDB when you need it: %sbrew services start mongodb-community%s\n' "$BOLD" "$RESET"
  printf '\n%sDone. Enjoy your fresh Mac.%s\n\n' "$GREEN" "$RESET"
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  banner
  show_plan       # show the whole roadmap before anything runs
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
