#!/usr/bin/env bash
#
# my-setup · fresh macOS bootstrap — https://github.com/gokhangunduz/my-setup
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/gokhangunduz/my-setup/main/install.sh)"
#
# Safe to re-run; edit the lists below to change what's installed.

# No set -e / -u: a failed step or unset variable must never abort the run.
set -o pipefail

# ─────────────────────────────────────────────────────────────────────────────
# What to install — edit these lists to taste.
# ─────────────────────────────────────────────────────────────────────────────

TAPS=(
  mongodb/brew
)

# Homebrew formulae. `git` is added automatically; postgresql/python track latest.
FORMULAE=(
  # runtimes
  node
  python
  # databases
  postgresql
  sqlite
  mongodb-community
  # cli tools
  gh
  hcloud
  awscli
  antidote
  dockutil
  mas
)

CASKS=(
  # browser
  google-chrome
  # dev tools
  visual-studio-code
  webstorm
  cursor
  docker-desktop
  postman
  # database GUIs
  mongodb-compass
  pgadmin4
  # design
  figma
  # AI
  chatgpt
  google-gemini
  claude
  claude-code
  codex-app
  # utilities
  logi-options+
  betterdisplay
  teamviewer
  nvidia-geforce-now
)

# Mac App Store apps via `mas`: "app-id|name". Sign into the App Store first.
MAS_APPS=(
  "497799835|Xcode"
  "310633997|WhatsApp"
  "640199958|Apple Developer"
)

# Apps appended to the Dock, in this order, after whatever's already there. Missing
# apps are skipped and present ones aren't re-added (uses the `dockutil` formula).
DOCK_APPS=(
  "/System/Applications/Utilities/Terminal.app"
  "/Applications/Visual Studio Code.app"
  "/Applications/Xcode.app"
  "/Applications/WebStorm.app"
  "/Applications/Cursor.app"
  "/Applications/Docker.app"
  "/Applications/Postman.app"
  "/Applications/pgAdmin 4.app"
  "/Applications/MongoDB Compass.app"
  "/Applications/Figma.app"
  "/Applications/Claude.app"
  "/Applications/Codex.app"
  "/Applications/Gemini.app"
  "/Applications/ChatGPT.app"
  "/Applications/Google Chrome.app"
  "/Applications/TeamViewer.app"
  "/Applications/GeForceNOW.app"
)

# antidote plugin list → ~/.zsh_plugins.txt. OMZ plugins load via ohmyzsh/ohmyzsh
# (use-omz + path:lib set them up). zsh-syntax-highlighting MUST stay last.
ZSH_PLUGINS=(
  "getantidote/use-omz"
  "ohmyzsh/ohmyzsh path:lib"
  "ohmyzsh/ohmyzsh path:plugins/git"
  "ohmyzsh/ohmyzsh path:plugins/brew"
  "ohmyzsh/ohmyzsh path:plugins/macos"
  "ohmyzsh/ohmyzsh path:plugins/docker"
  "ohmyzsh/ohmyzsh path:plugins/docker-compose"
  "ohmyzsh/ohmyzsh path:plugins/gh"
  "ohmyzsh/ohmyzsh path:plugins/aws"
  "ohmyzsh/ohmyzsh path:plugins/npm"
  "ohmyzsh/ohmyzsh path:plugins/node"
  "ohmyzsh/ohmyzsh path:plugins/command-not-found"
  "romkatv/powerlevel10k"
  "zsh-users/zsh-completions"
  "zsh-users/zsh-autosuggestions"
  "zsh-users/zsh-syntax-highlighting"
)

GIT_NAME="gokhangunduz"
GIT_EMAIL="me@gokhangunduz.dev"

# ─────────────────────────────────────────────────────────────────────────────
# Internals — you usually don't need to touch anything below here.
# ─────────────────────────────────────────────────────────────────────────────

# Result tallies, shown in the end card.
INSTALLED=0; UPDATED=0; SKIPPED=0; FAILED=0

ERROR_LOG="$(mktemp -t mysetup-errors 2>/dev/null || echo /tmp/mysetup-errors.$$)"
SWUPDATE_CACHE="$(mktemp -t mysetup-swupdate 2>/dev/null || echo /tmp/mysetup-swupdate.$$)"
SUDO_KEEPALIVE_PID=""; SUDO_AUTHENTICATED=0
SUDOERS_FILE="/etc/sudoers.d/my-setup"; SUDOERS_INSTALLED=0
TASK_TIMEOUT=1800   # seconds: kill any task that hangs longer, then carry on
TUI_ACTIVE=0
SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
STEP_BADGES=(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩)

# 256-color palette, disabled when output isn't a terminal.
if [ -t 1 ]; then
  BOLD=$'\033[1m'; RESET=$'\033[0m'
  ACCENT=$'\033[38;5;141m'; GREEN=$'\033[38;5;114m'; CYAN=$'\033[38;5;116m'
  YELLOW=$'\033[38;5;179m'; RED=$'\033[38;5;203m'; MUTED=$'\033[38;5;245m'; RULE=$'\033[38;5;240m'
else
  BOLD=""; RESET=""; ACCENT=""; GREEN=""; CYAN=""; YELLOW=""; RED=""; MUTED=""; RULE=""
fi

cleanup() {
  [ "$TUI_ACTIVE" = "1" ] && printf '\033[?25h'
  [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
  [ "$SUDOERS_INSTALLED" = "1" ] && sudo rm -f "$SUDOERS_FILE" 2>/dev/null
  [ "$SUDO_AUTHENTICATED" = "1" ] && sudo -k 2>/dev/null
  rm -f "$ERROR_LOG" "$SWUPDATE_CACHE" 2>/dev/null
}
trap cleanup EXIT INT TERM

format_duration() {
  local seconds=$1
  if [ "$seconds" -lt 60 ]; then printf '%ds' "$seconds"
  else printf '%dm%02ds' $((seconds / 60)) $((seconds % 60)); fi
}

# ── Task commands ────────────────────────────────────────────────────────────
# Each returns 10 when already in the desired state (shown as ⊘ skipped).

# A running task records its current action (installing/upgrading/…) here; the live
# view reads it each frame and shows it next to the spinner.
set_phase() { [ -n "$PHASE_FILE" ] && printf '%s' "$1" >"$PHASE_FILE"; }

configure_git() {
  [ "$(git config --global user.name 2>/dev/null)" = "$GIT_NAME" ] \
    && [ "$(git config --global user.email 2>/dev/null)" = "$GIT_EMAIL" ] \
    && [ "$(git config --global pull.rebase 2>/dev/null)" = "false" ] && return 10
  git config --global user.name "$GIT_NAME" &&
  git config --global user.email "$GIT_EMAIL" &&
  git config --global init.defaultBranch main &&
  git config --global color.ui true &&
  git config --global pull.rebase false
}

write_zsh_plugins() {
  local file="$HOME/.zsh_plugins.txt" tmp; tmp="$(mktemp)"
  printf '%s\n' "${ZSH_PLUGINS[@]}" >"$tmp"
  if [ -f "$file" ] && cmp -s "$tmp" "$file"; then rm -f "$tmp"; return 10; fi
  mv "$tmp" "$file"
}

# Fenced block in ~/.zshrc so we never clobber the user's lines. Markers must stay
# free of regex-special characters (they're used as awk patterns below).
ZSHRC_MARK_BEGIN="# my-setup antidote begin"
ZSHRC_MARK_END="# my-setup antidote end"
zshrc_block() {
  cat <<'BLK'
# my-setup antidote begin
# Powerlevel10k instant prompt — keep this near the top.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
# antidote — clones and loads every plugin listed in ~/.zsh_plugins.txt
for _brew_prefix in "${HOMEBREW_PREFIX:-/opt/homebrew}" /opt/homebrew /usr/local; do
  [[ -r "$_brew_prefix/share/antidote/antidote.zsh" ]] && { source "$_brew_prefix/share/antidote/antidote.zsh"; break; }
done
unset _brew_prefix
antidote load
autoload -Uz compinit && compinit -u
[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
# my-setup antidote end
BLK
}

write_zshrc() {
  local file="$HOME/.zshrc"; [ -f "$file" ] || touch "$file"
  local want current tmp; want="$(mktemp)"; current="$(mktemp)"
  zshrc_block >"$want"
  awk -v b="$ZSHRC_MARK_BEGIN" -v e="$ZSHRC_MARK_END" '$0 ~ b {f=1} f {print} $0 ~ e {f=0}' "$file" >"$current"
  if cmp -s "$want" "$current"; then rm -f "$want" "$current"; return 10; fi
  tmp="$(mktemp)"
  awk -v b="$ZSHRC_MARK_BEGIN" -v e="$ZSHRC_MARK_END" '$0 ~ b {skip=1} skip!=1 {print} $0 ~ e {skip=0}' "$file" >"$tmp"
  printf '\n' >>"$tmp"; cat "$want" >>"$tmp"
  mv "$tmp" "$file"; rm -f "$want" "$current"
}

enable_dark_mode() {
  [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ] && return 10
  defaults write -g AppleInterfaceStyle -string Dark
}
enable_dark_app_icons() {
  [ "$(defaults read -g AppleIconAppearanceTheme 2>/dev/null)" = "RegularDark" ] && return 10
  defaults write -g AppleIconAppearanceTheme -string RegularDark
}
configure_dock() {
  [ "$(defaults read com.apple.dock tilesize 2>/dev/null)" = "64" ] \
    && [ "$(defaults read com.apple.dock magnification 2>/dev/null)" = "1" ] \
    && [ "$(defaults read com.apple.dock largesize 2>/dev/null)" = "92" ] && return 10
  defaults write com.apple.dock tilesize -int 64 &&
  defaults write com.apple.dock magnification -bool true &&
  defaults write com.apple.dock largesize -int 92
  killall Dock 2>/dev/null; return 0
}
# Append DOCK_APPS after the current Dock items, in order. Skips apps that aren't
# installed and ones already in the Dock; returns 10 when there's nothing to add.
arrange_dock_apps() {
  command -v dockutil >/dev/null 2>&1 || return 10
  set_phase arranging
  local app encoded added=0 current
  current="$(defaults read com.apple.dock persistent-apps 2>/dev/null)"
  for app in "${DOCK_APPS[@]}"; do
    [ -d "$app" ] || continue                                  # not installed → skip
    encoded="$(printf '%s' "$app" | sed 's/ /%20/g')"          # match the plist's URL form
    printf '%s' "$current" | grep -qF "$encoded" && continue   # already in the Dock
    dockutil --add "$app" --no-restart >/dev/null 2>&1 && added=$((added + 1))
  done
  [ "$added" -eq 0 ] && return 10
  killall Dock 2>/dev/null; return 0
}
# Cmd+" → "Move focus to next window" (hotkey 27). params = (34=", 10=key code on
# this layout, 1048576=Cmd), captured from System Settings; re-capture if it differs.
set_next_window_shortcut() {
  local plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:27:value:parameters:0' "$plist" 2>/dev/null)" = "34" ] \
    && [ "$(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:27:value:parameters:1' "$plist" 2>/dev/null)" = "10" ] \
    && [ "$(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:27:value:parameters:2' "$plist" 2>/dev/null)" = "1048576" ] && return 10
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 27 \
    '{enabled=1;value={parameters=(34,10,1048576);type=standard;};}' || return 1
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
}
enable_firewall() {
  /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q 'State = 1' && return 10
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
}
configure_power() {
  local settings battery ac
  settings="$(pmset -g custom 2>/dev/null)"
  battery="$(printf '%s' "$settings" | sed -n '/Battery/,/AC Power/p')"
  ac="$(printf '%s' "$settings" | sed -n '/AC Power/,$p')"
  printf '%s' "$battery" | grep -qE 'lessbright[[:space:]]+1' \
    && printf '%s' "$battery" | grep -qE 'womp[[:space:]]+0' \
    && printf '%s' "$ac" | grep -qE '[^a-z]sleep[[:space:]]+0' \
    && printf '%s' "$ac" | grep -qE 'womp[[:space:]]+1' && return 10
  sudo pmset -b lessbright 1 &&   # dim on battery
  sudo pmset -c sleep 0 &&        # never auto-sleep on AC
  sudo pmset -c womp 1 &&         # wake for network on AC
  sudo pmset -b womp 0            # ...but not on battery
}
set_local_hostname() {
  [ "$(scutil --get LocalHostName 2>/dev/null)" = "gg" ] && return 10
  sudo scutil --set LocalHostName gg
}

# Final tidy-up: drop old Homebrew versions and the whole download cache.
clean_caches() {
  set_phase cleaning
  brew cleanup --prune=all -s >/dev/null 2>&1
  local cache; cache="$(brew --cache 2>/dev/null)"
  [ -n "$cache" ] && [ -d "$cache" ] && rm -rf "${cache:?}"/* 2>/dev/null
  return 0
}

# ── Preflight, sudo, Homebrew (prepare phase, before the live view) ──────────

preflight() {
  if [ "$(uname -s)" != "Darwin" ]; then printf '%sThis installer is for macOS only.%s\n' "$RED" "$RESET"; exit 1; fi
  if [ "$(uname -m)" = "arm64" ]; then BREW_PREFIX="/opt/homebrew"; else BREW_PREFIX="/usr/local"; fi
}

# One password prompt, then a temporary passwordless-sudo rule (revoked on exit).
acquire_sudo() {
  printf '  %s🔑  Enter your macOS password once — then it runs unattended.%s\n' "$MUTED" "$RESET"
  if ! sudo -v; then printf '  %s✗ Administrator access is required (your account must be an admin).%s\n' "$RED" "$RESET"; exit 1; fi
  SUDO_AUTHENTICATED=1
  if printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$(id -un)" | sudo tee "$SUDOERS_FILE" >/dev/null 2>&1 \
     && sudo chmod 440 "$SUDOERS_FILE" 2>/dev/null && sudo visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
    SUDOERS_INSTALLED=1
  else
    sudo rm -f "$SUDOERS_FILE" 2>/dev/null
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
  fi
}

# Homebrew: install if missing, else update; return 10 if already up to date.
ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    set_phase updating
    local output; output="$(brew update 2>&1)"
    printf '%s' "$output" | grep -qi 'already up-to-date' && return 10
    return 0
  fi
  set_phase installing
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
  [ -x "$BREW_PREFIX/bin/brew" ] || command -v brew >/dev/null 2>&1
}
# Put brew on PATH for the rest of the run + future shells. Runs in the PARENT.
add_brew_to_path() {
  BREW_PREFIX="$(brew --prefix 2>/dev/null || echo "$BREW_PREFIX")"
  eval "$("$BREW_PREFIX/bin/brew" shellenv 2>/dev/null)"
  grep -qsF '/brew shellenv' "$HOME/.zprofile" 2>/dev/null \
    || printf '\neval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX" >>"$HOME/.zprofile"
}

# ── Task model ───────────────────────────────────────────────────────────────
# Eight steps; tasks are flat parallel arrays so the renderer can group/count them.

STEP_ICONS=(🍺 🐙 🧰 📦 🛒 🐚 🎨 🔄 🧹)
STEP_NAMES=("Homebrew" "Git" "Formulae" "Casks" "Mac App Store" "Shell" "macOS Settings" "macOS Updates" "Cleanup")
STEP_COUNT=${#STEP_NAMES[@]}

# Parallel arrays, one slot per task. status ∈ pending|run|ok|upd|skip|fail.
TASK_STEP=(); TASK_LABEL=(); TASK_KIND=(); TASK_ARG=(); TASK_STATUS=(); TASK_TIME=()
add_task() {
  TASK_STEP+=("$1"); TASK_LABEL+=("$2"); TASK_KIND+=("$3"); TASK_ARG+=("$4")
  TASK_STATUS+=("pending"); TASK_TIME+=("")
}

build_task_list() {
  local item id name
  # 0 · Homebrew
  add_task 0 "package manager" homebrew ""
  # 1 · Git (install + config, separate tasks)
  add_task 1 "git" formula "git"
  add_task 1 "git config" fn configure_git
  # 2 · Formulae (taps first)
  for item in "${TAPS[@]}"; do add_task 2 "tap ${item}" tap "$item"; done
  for item in "${FORMULAE[@]}"; do add_task 2 "$item" formula "$item"; done
  # 3 · Casks
  for item in "${CASKS[@]}"; do add_task 3 "$item" cask "$item"; done
  # 4 · Mac App Store — installs trigger here so the Dock step (later) can see them
  for item in "${MAS_APPS[@]}"; do id="${item%%|*}"; name="${item##*|}"; add_task 4 "$name" mas "$id"; done
  # 5 · Shell (antidote plugin list + .zshrc)
  add_task 5 ".zsh_plugins.txt" fn write_zsh_plugins
  add_task 5 ".zshrc" fn write_zshrc
  # 6 · macOS Settings (Dock Apps last, after every app is installed/triggered)
  add_task 6 "Theme Mode" fn enable_dark_mode
  add_task 6 "App Icons" fn enable_dark_app_icons
  add_task 6 "Dock Settings" fn configure_dock
  add_task 6 "Dock Apps" fn arrange_dock_apps
  add_task 6 "Shortcuts" fn set_next_window_shortcut
  add_task 6 "Firewall" fn enable_firewall
  add_task 6 "Battery" fn configure_power
  add_task 6 "Hostname" fn set_local_hostname
  # 7 · macOS Updates (CLT + macOS, checked separately)
  add_task 7 "Command Line Tools" clt ""
  add_task 7 "macOS" macos ""
  # 8 · Cleanup — runs last, after everything else
  add_task 8 "caches" fn clean_caches
}

# Install $name if missing, upgrade if outdated, else leave it. $flag is the
# Homebrew type (--formula/--cask). exit 0 installed · 11 upgraded · 10 current.
ensure_brew_package() {
  local flag="$1" name="$2" extra=()
  [ "$flag" = "--cask" ] && extra=(--adopt)   # take over an app that's already in /Applications
  brew list "$flag" --versions "$name" >/dev/null 2>&1 || { set_phase installing; brew install "$flag" "${extra[@]}" "$name" || exit 1; exit 0; }
  [ -n "$(brew outdated "$flag" "$name" 2>/dev/null)" ] && { set_phase upgrading; brew upgrade "$flag" "$name" || exit 1; exit 11; }
  exit 10
}

# Run one task (in a subshell). Exit code: 0 done · 10 skipped · 11 updated · else failed.
run_task() {
  local kind="${TASK_KIND[$1]}" arg="${TASK_ARG[$1]}"
  case "$kind" in
    homebrew) ensure_homebrew; exit $? ;;
    fn)      "$arg"; exit $? ;;
    tap)     if brew tap 2>/dev/null | grep -qxF "$arg"; then brew trust --tap "$arg" >/dev/null 2>&1; exit 10; fi
             set_phase tapping; brew tap "$arg" || exit 1; brew trust --tap "$arg" >/dev/null 2>&1; exit 0 ;;
    formula) ensure_brew_package --formula "$arg" ;;
    cask)    ensure_brew_package --cask "$arg" ;;
    mas)     mas list 2>/dev/null | grep -q "^$arg " && exit 10        # already installed → skip
             set_phase downloading
             nohup mas install "$arg" >/dev/null 2>&1 &              # trigger, don't wait for the (huge) download
             local mpid=$!; sleep 2
             kill -0 "$mpid" 2>/dev/null && exit 0                   # still downloading → started
             wait "$mpid" 2>/dev/null && exit 0 || exit 10 ;;        # finished fast: ok, or not signed in → skip
    clt)     set_phase checking; softwareupdate -l >"$SWUPDATE_CACHE" 2>&1   # one query to Apple, cached for the macOS task
             local label; label="$(grep 'Label:' "$SWUPDATE_CACHE" 2>/dev/null | grep -i 'Command Line Tools' | sed -E 's/.*Label: *//; s/ *$//' | head -1)"
             [ -z "$label" ] && exit 10
             set_phase downloading; nohup sudo softwareupdate --download "$label" >/dev/null 2>&1 & exit 0 ;;
    macos)   set_phase checking; local labels=() label
             while IFS= read -r label; do
               label="$(printf '%s' "$label" | sed -E 's/.*Label: *//; s/ *$//')"
               [ -n "$label" ] && labels+=("$label")
             done < <(grep 'Label:' "$SWUPDATE_CACHE" 2>/dev/null | grep -vi 'Command Line Tools')
             [ "${#labels[@]}" -eq 0 ] && exit 10
             set_phase downloading; nohup sudo softwareupdate --download "${labels[@]}" >/dev/null 2>&1 & exit 0 ;;
  esac
  exit 0
}

# Map a finished task's exit code to its status and bump the matching tally.
record_result() {
  local index="$1" code="$2" log="$3" kind="${TASK_KIND[$1]}" label="${TASK_LABEL[$1]}"
  case "$code" in
    0)  TASK_STATUS[$index]="ok";   INSTALLED=$((INSTALLED + 1)) ;;
    11) TASK_STATUS[$index]="upd";  UPDATED=$((UPDATED + 1)) ;;
    10) TASK_STATUS[$index]="skip"; SKIPPED=$((SKIPPED + 1)) ;;
    *)  TASK_STATUS[$index]="fail"; FAILED=$((FAILED + 1)); { printf '\n=== %s ===\n' "$label"; cat "$log"; } >>"$ERROR_LOG" ;;
  esac
  case "$kind" in clt|macos|mas) [ "$code" = 0 ] && TASK_TIME[$index]="started" ;; esac
}

# ── Live full-screen view ────────────────────────────────────────────────────

ACTIVE_STEP=0; SPIN_FRAME=0; LABEL_WIDTH=30
ACTIVE_DETAIL=""     # live action word (installing/upgrading/…) for the running task
PHASE_FILE=""        # the running subshell writes its current action to this file
CLEAR_EOL=$'\033[K'   # clear to end of line so a shrinking line leaves no stale tail

# Echo "<total> <finished>" for the tasks belonging to step $1.
step_progress() {
  local step="$1" total=0 finished=0 i
  for i in "${!TASK_STEP[@]}"; do
    [ "${TASK_STEP[$i]}" = "$step" ] || continue
    total=$((total + 1))
    case "${TASK_STATUS[$i]}" in ok|skip|upd|fail) finished=$((finished + 1)) ;; esac
  done
  printf '%d %d' "$total" "$finished"
}

render_task() {
  local index="$1" status="${TASK_STATUS[$1]}" label="${TASK_LABEL[$1]}" elapsed="${TASK_TIME[$1]}"
  local glyph glyph_color detail detail_color="$MUTED"
  case "$status" in
    pending) glyph="○"; glyph_color="$RULE";   detail="" ;;
    run)     glyph="${SPINNER[SPIN_FRAME % ${#SPINNER[@]}]}"; glyph_color="$ACCENT"; detail="$ACTIVE_DETAIL" ;;
    ok)      glyph="✓"; glyph_color="$GREEN";  detail="$elapsed" ;;
    upd)     glyph="↑"; glyph_color="$CYAN";   detail="${elapsed:-updated}" ;;
    skip)    glyph="⊘"; glyph_color="$MUTED";  detail="skipped" ;;
    fail)    glyph="✗"; glyph_color="$RED";    detail="failed"; detail_color="$RED" ;;
  esac
  printf '      %s%s%s  %-*s %s%s%s%s' \
    "$glyph_color" "$glyph" "$RESET" "$LABEL_WIDTH" "$label" "$detail_color" "$detail" "$RESET" "$CLEAR_EOL"
}

# Every step stays expanded: header (✓ done / ▸ active / ○ upcoming) + all its rows.
render_step() {
  local step="$1" badge="${STEP_BADGES[$1]}" icon="${STEP_ICONS[$1]}" name="${STEP_NAMES[$1]}"
  local total finished i head_glyph head_color
  read -r total finished <<<"$(step_progress "$step")"
  total="${total:-0}"; finished="${finished:-0}"   # stay numeric even if interrupted
  if [ "$total" -gt 0 ] && [ "$finished" -ge "$total" ]; then head_glyph="✓"; head_color="$GREEN"
  elif [ "$step" -le "$ACTIVE_STEP" ]; then head_glyph="▸"; head_color="$ACCENT"
  else head_glyph="○"; head_color="$RULE"; fi
  printf '  %s%s%s %s %s  %s%s%s   %s%d/%d%s%s\n' \
    "$head_color" "$head_glyph" "$RESET" "$badge" "$icon" "$ACCENT$BOLD" "$name" "$RESET" "$MUTED" "$finished" "$total" "$RESET" "$CLEAR_EOL"
  for i in "${!TASK_STEP[@]}"; do [ "${TASK_STEP[$i]}" = "$step" ] && { render_task "$i"; printf '\n'; }; done
}

# The whole frame as text (no cursor moves) — banner, every step, footer.
render_body() {
  local finished=0 total="${#TASK_LABEL[@]}" pct=0 i step
  for i in "${!TASK_STATUS[@]}"; do case "${TASK_STATUS[$i]}" in ok|skip|upd|fail) finished=$((finished + 1)) ;; esac; done
  [ "$total" -gt 0 ] && pct=$(( finished * 100 / total ))
  printf '  %s%s❖  my-setup%s  %s· fresh macOS bootstrap%s%s\n%s\n' "$ACCENT" "$BOLD" "$RESET" "$MUTED" "$RESET" "$CLEAR_EOL" "$CLEAR_EOL"
  for step in $(seq 0 $((STEP_COUNT - 1))); do render_step "$step"; done
  printf '%s\n  %s%d%%%s  %s%d/%d tasks%s%s\n' \
    "$CLEAR_EOL" "$ACCENT$BOLD" "$pct" "$RESET" "$MUTED" "$finished" "$total" "$RESET" "$CLEAR_EOL"
}

# Redraw the whole frame in place: home, body, clear anything left below. No line
# math — this is only ever used when the frame fits the terminal (see fits_live_view).
render() { printf '\033[H'; render_body; printf '\033[J'; }

new_log_file() { mktemp -t mysetup 2>/dev/null || echo "/tmp/mysetup.$$.$RANDOM"; }

# Post-run bookkeeping shared by both renderers: put brew on PATH after the
# Homebrew step (parent side), record elapsed time, tally the result, drop the log.
complete_task() {
  local index="$1" code="$2" log="$3" started="$4" elapsed
  [ "${TASK_KIND[$index]}" = "homebrew" ] && [ "$code" -ne 1 ] && add_brew_to_path
  elapsed=$((SECONDS - started)); [ "$elapsed" -ge 1 ] && TASK_TIME[$index]="$(format_duration "$elapsed")"
  record_result "$index" "$code" "$log"; rm -f "$log"
}

# Run one task in the background, polling at ~10fps with a timeout, calling the
# frame hook ($2) each tick so a view can animate. Shared by all three renderers.
drive_task() {
  local index="$1" on_frame="$2" pid code started log
  TASK_STATUS[$index]="run"; ACTIVE_DETAIL=""
  log="$(new_log_file)"; PHASE_FILE="$(new_log_file)"; : >"$PHASE_FILE"; started=$SECONDS
  ( run_task "$index" ) >"$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$((SECONDS - started))" -ge "$TASK_TIMEOUT" ]; then
      printf '\n[my-setup] task exceeded %ss — terminated so the run can continue\n' "$TASK_TIMEOUT" >>"$log"
      kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null; break
    fi
    [ -s "$PHASE_FILE" ] && ACTIVE_DETAIL="$(cat "$PHASE_FILE" 2>/dev/null)"   # live action word
    "$on_frame" "$index"; SPIN_FRAME=$((SPIN_FRAME + 1)); sleep 0.1
  done
  { wait "$pid"; } 2>/dev/null; code=$?
  rm -f "$PHASE_FILE"
  complete_task "$index" "$code" "$log" "$started"
}

# Interactive, terminal tall enough: the full-screen dashboard, redrawn in place.
run_live_view() {
  printf '\033[2J\033[H\033[?25l'; TUI_ACTIVE=1
  local index
  for index in "${!TASK_LABEL[@]}"; do
    ACTIVE_STEP="${TASK_STEP[$index]}"
    drive_task "$index" render
    render
  done
  ACTIVE_STEP=99   # 99 = past the last step, so every header reads ✓
  printf '\033[2J\033[H'; render_body   # dump the whole finished view so it all persists
  printf '\033[?25h'; TUI_ACTIVE=0
}

# Interactive, shorter terminal: a streaming log — each task animates in place on
# one line (spinner + action), then commits to its final colored row and scrolls up.
_stream_frame() { printf '\r'; render_task "$1"; }
run_stream() {
  printf '\033[?25l'; TUI_ACTIVE=1
  local index current_step=-1
  for index in "${!TASK_LABEL[@]}"; do
    if [ "${TASK_STEP[$index]}" != "$current_step" ]; then
      current_step="${TASK_STEP[$index]}"
      printf '\n  %s%s%s %s  %s%s%s\n' \
        "$ACCENT" "${STEP_BADGES[$current_step]}" "$RESET" "${STEP_ICONS[$current_step]}" "$ACCENT$BOLD" "${STEP_NAMES[$current_step]}" "$RESET"
    fi
    drive_task "$index" _stream_frame
    printf '\r'; render_task "$index"; printf '\n'   # commit the final row
  done
  printf '\033[?25h'; TUI_ACTIVE=0
}

# Non-interactive (logs / CI): plain sequential lines, no cursor tricks.
run_plain_output() {
  local index current_step=-1
  for index in "${!TASK_LABEL[@]}"; do
    [ "${TASK_STEP[$index]}" != "$current_step" ] \
      && { current_step="${TASK_STEP[$index]}"; printf '\n%s %s\n' "${STEP_BADGES[$current_step]}" "${STEP_NAMES[$current_step]}"; }
    drive_task "$index" :
    case "${TASK_STATUS[$index]}" in
      ok)   printf '  + %s %s\n' "${TASK_LABEL[$index]}" "${TASK_TIME[$index]}" ;;
      upd)  printf '  ^ %s (updated)\n' "${TASK_LABEL[$index]}" ;;
      skip) printf '  . %s (skipped)\n' "${TASK_LABEL[$index]}" ;;
      fail) printf '  x %s (failed)\n' "${TASK_LABEL[$index]}" ;;
    esac
  done
}

# ── Summary ──────────────────────────────────────────────────────────────────

print_summary() {
  printf '\n  %s%s❖  my-setup%s  %s· done in %s%s\n' "$ACCENT" "$BOLD" "$RESET" "$MUTED" "$(format_duration "$SECONDS")" "$RESET"
  printf '  %s%s✓ %d installed%s   %s↑ %d updated%s   %s⊘ %d skipped%s   %s✗ %d failed%s\n' \
    "$GREEN" "$BOLD" "$INSTALLED" "$RESET" "$CYAN" "$UPDATED" "$RESET" \
    "$MUTED" "$SKIPPED" "$RESET" "$RED" "$FAILED" "$RESET"
  if [ "$FAILED" -gt 0 ]; then
    printf '\n  %sFailures — re-run to retry (finished steps are skipped):%s\n' "$YELLOW" "$RESET"
    sed 's/^/    /' "$ERROR_LOG"
  fi
  printf '\n'
}

# ── Main ─────────────────────────────────────────────────────────────────────

# Use the in-place dashboard only when the whole frame fits the terminal (banner +
# step headers + every task + footer). Otherwise the plain stream, which scrolls
# cleanly at any size. Just a height check — no per-line math.
fits_live_view() {
  local rows; rows="$(stty size 2>/dev/null | awk '{print $1}')"   # ioctl size; reliable
  case "$rows" in ''|*[!0-9]*) rows="$(tput lines 2>/dev/null)" ;; esac
  case "$rows" in ''|*[!0-9]*) rows=0 ;; esac
  [ "$rows" -ge "$(( ${#TASK_LABEL[@]} + STEP_COUNT + 5 ))" ]
}

main() {
  preflight
  printf '\n  %s%s❖  my-setup%s  %s· fresh macOS bootstrap%s\n\n' "$ACCENT" "$BOLD" "$RESET" "$MUTED" "$RESET"
  acquire_sudo
  build_task_list
  if [ ! -t 1 ]; then run_plain_output            # logs / CI
  elif fits_live_view; then run_live_view          # tall terminal: full dashboard
  else run_stream; fi                              # shorter terminal: animated stream
  print_summary
}

main "$@"
