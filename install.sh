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
# unexpected unset/empty variable must never crash it either). Each task handles
# its own success/failure and the run always moves on to the next one.
set -o pipefail

# ─────────────────────────────────────────────────────────────────────────────
# What to install — edit these lists to taste.
# ─────────────────────────────────────────────────────────────────────────────

# Extra Homebrew taps needed by some formulae below (tapped before installing).
TAPS=(
  mongodb/brew
)

# Homebrew formulae (CLI tools + servers). `git` is added automatically.
# `postgresql` / `python` are aliases that always point at the latest version;
# mongodb-community is the latest MongoDB Community (from the mongodb/brew tap).
FORMULAE=(
  node
  python
  postgresql
  mongodb-community
  mas
)

# Applications (Homebrew casks).
CASKS=(
  # browser
  google-chrome
  # dev tools
  visual-studio-code
  webstorm
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

DONE=0; SKIPPED=0; FAILED=0
RECAP_INSTALLED=""; RECAP_UPDATED=""; RECAP_SKIPPED=""; RECAP_FAILED=""
ERR_LOG="$(mktemp -t mysetup-errors 2>/dev/null || echo /tmp/mysetup-errors.$$)"
SU_CACHE="$(mktemp -t mysetup-swupdate 2>/dev/null || echo /tmp/mysetup-swupdate.$$)"
SUDO_KEEPALIVE_PID=""; SUDO_PRIMED=0
SUDOERS_FILE="/etc/sudoers.d/my-setup"; SUDOERS_INSTALLED=0
STEP_TIMEOUT=1800   # seconds: kill any single task that hangs longer, then continue
TUI_ACTIVE=0
SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
CIRCLED=(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩)

# 256-color palette (disabled when not a terminal): violet accent + semantics.
if [ -t 1 ]; then
  BOLD=$'\033[1m'; RESET=$'\033[0m'
  ACCENT=$'\033[38;5;141m'; GREEN=$'\033[38;5;114m'; CYAN=$'\033[38;5;116m'
  YELLOW=$'\033[38;5;179m'; RED=$'\033[38;5;203m'; MUTED=$'\033[38;5;245m'; RULE=$'\033[38;5;240m'
else
  BOLD=""; RESET=""; ACCENT=""; GREEN=""; CYAN=""; YELLOW=""; RED=""; MUTED=""; RULE=""
fi

cleanup() {
  [ "$TUI_ACTIVE" = "1" ] && printf '\033[?25h'   # always free the cursor again
  [ -n "$SUDO_KEEPALIVE_PID" ] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
  [ "$SUDOERS_INSTALLED" = "1" ] && sudo rm -f "$SUDOERS_FILE" 2>/dev/null
  [ "$SUDO_PRIMED" = "1" ] && sudo -k 2>/dev/null
  rm -f "$ERR_LOG" "$SU_CACHE" 2>/dev/null
}
trap cleanup EXIT INT TERM

fmt_secs() { local s=$1; if [ "$s" -lt 60 ]; then printf '%ds' "$s"; else printf '%dm%02ds' $((s / 60)) $((s % 60)); fi; }
rec_installed() { RECAP_INSTALLED="${RECAP_INSTALLED}"$'\n'"$1"; }
rec_updated()   { RECAP_UPDATED="${RECAP_UPDATED}"$'\n'"$1"; }
rec_skipped()   { RECAP_SKIPPED="${RECAP_SKIPPED}"$'\n'"$1"; }
note_fail()     { FAILED=$((FAILED + 1)); RECAP_FAILED="${RECAP_FAILED}"$'\n'"$1"; }
_count() { local n=0 l; while IFS= read -r l; do [ -n "$l" ] && n=$((n + 1)); done <<EOF
$1
EOF
printf '%d' "$n"; }

# ── Commands the tasks run ───────────────────────────────────────────────────

# Every settings/config task returns 10 ("skip") when it's already in the desired
# state, so re-runs don't redo work — and the live view shows ⊘ instead of ✓.

_git_config() {
  [ "$(git config --global user.name 2>/dev/null)" = "$GIT_NAME" ] \
    && [ "$(git config --global user.email 2>/dev/null)" = "$GIT_EMAIL" ] \
    && [ "$(git config --global pull.rebase 2>/dev/null)" = "false" ] && return 10
  git config --global user.name "$GIT_NAME" &&
  git config --global user.email "$GIT_EMAIL" &&
  git config --global init.defaultBranch main &&
  git config --global color.ui true &&
  git config --global pull.rebase false
}

_install_omz() {
  local s; s="$(mktemp -t omz 2>/dev/null || echo "/tmp/omz.$$")"
  curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$s" || return 1
  sh "$s" --unattended; local rc=$?; rm -f "$s"; return $rc   # --unattended ⇒ no exec zsh / no chsh
}

_configure_zshrc() {
  local rc="$HOME/.zshrc"; [ -f "$rc" ] || touch "$rc"
  grep -qF "ZSH_THEME=\"$ZSH_THEME_VALUE\"" "$rc" \
    && grep -qF "plugins=($ZSH_PLUGINS_VALUE)" "$rc" && return 10
  grep -q '^ZSH_THEME=' "$rc" \
    && sed -i '' "s|^ZSH_THEME=.*|ZSH_THEME=\"$ZSH_THEME_VALUE\"|" "$rc" \
    || printf '\nZSH_THEME="%s"\n' "$ZSH_THEME_VALUE" >>"$rc"
  grep -q '^plugins=' "$rc" \
    && sed -i '' "s|^plugins=.*|plugins=($ZSH_PLUGINS_VALUE)|" "$rc" \
    || printf '\nplugins=(%s)\n' "$ZSH_PLUGINS_VALUE" >>"$rc"
}

_appearance_prefs() {
  [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ] && return 10
  defaults write -g AppleInterfaceStyle -string Dark
}
_appicons_prefs() {
  [ "$(defaults read -g AppleIconAppearanceTheme 2>/dev/null)" = "RegularDark" ] && return 10
  defaults write -g AppleIconAppearanceTheme -string RegularDark
}
_dock_prefs() {
  [ "$(defaults read com.apple.dock tilesize 2>/dev/null)" = "64" ] \
    && [ "$(defaults read com.apple.dock magnification 2>/dev/null)" = "1" ] \
    && [ "$(defaults read com.apple.dock largesize 2>/dev/null)" = "92" ] && return 10
  defaults write com.apple.dock tilesize -int 64 &&
  defaults write com.apple.dock magnification -bool true &&
  defaults write com.apple.dock largesize -int 92
  killall Dock 2>/dev/null; return 0
}
# Cmd+" → "Move focus to next window" (symbolic hotkey 27). parameters =
# (34 = ", 10 = its key code on this keyboard layout, 1048576 = Cmd) — captured
# verbatim from System Settings; re-capture if your keyboard layout differs.
_keyboard_shortcut() {
  local p="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:27:value:parameters:0' "$p" 2>/dev/null)" = "34" ] \
    && [ "$(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:27:value:parameters:1' "$p" 2>/dev/null)" = "10" ] \
    && [ "$(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:27:value:parameters:2' "$p" 2>/dev/null)" = "1048576" ] && return 10
  defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 27 \
    '{enabled=1;value={parameters=(34,10,1048576);type=standard;};}' || return 1
  /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u 2>/dev/null || true
}
_firewall_on() {
  /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | grep -q 'State = 1' && return 10
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
}
_battery_prefs() {
  local cust; cust="$(pmset -g custom 2>/dev/null)"
  printf '%s' "$cust" | sed -n '/Battery/,/AC Power/p' | grep -qE 'lessbright[[:space:]]+1' \
    && printf '%s' "$cust" | sed -n '/Battery/,/AC Power/p' | grep -qE 'womp[[:space:]]+0' \
    && printf '%s' "$cust" | sed -n '/AC Power/,$p' | grep -qE '[^a-z]sleep[[:space:]]+0' \
    && printf '%s' "$cust" | sed -n '/AC Power/,$p' | grep -qE 'womp[[:space:]]+1' && return 10
  sudo pmset -b lessbright 1 &&   # dim the display on battery
  sudo pmset -c sleep 0 &&        # never auto-sleep on power adapter
  sudo pmset -c womp 1 &&         # wake for network access on power adapter
  sudo pmset -b womp 0            # ...but not on battery
}
_hostname_set() {
  [ "$(scutil --get LocalHostName 2>/dev/null)" = "gg" ] && return 10
  sudo scutil --set LocalHostName gg
}

# ── Preflight, sudo, Homebrew (prepare phase, before the live view) ──────────

preflight() {
  if [ "$(uname -s)" != "Darwin" ]; then printf '%sThis installer is for macOS only.%s\n' "$RED" "$RESET"; exit 1; fi
  if [ "$(uname -m)" = "arm64" ]; then BREW_PREFIX="/opt/homebrew"; else BREW_PREFIX="/usr/local"; fi
}

# Ask for the password once, then drop a temporary passwordless-sudo rule so
# nothing prompts again mid-run (revoked on exit, see cleanup).
prime_sudo() {
  printf '  %s🔑  Enter your macOS password once — then it runs unattended.%s\n' "$MUTED" "$RESET"
  if ! sudo -v; then printf '  %s✗ Administrator access is required (your account must be an admin).%s\n' "$RED" "$RESET"; exit 1; fi
  SUDO_PRIMED=1
  if printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$(id -un)" | sudo tee "$SUDOERS_FILE" >/dev/null 2>&1 \
     && sudo chmod 440 "$SUDOERS_FILE" 2>/dev/null && sudo visudo -cf "$SUDOERS_FILE" >/dev/null 2>&1; then
    SUDOERS_INSTALLED=1
  else
    sudo rm -f "$SUDOERS_FILE" 2>/dev/null
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 60; done ) &
    SUDO_KEEPALIVE_PID=$!
  fi
}

# The single Homebrew task (runs in a subshell): install if missing, otherwise
# update — and return 10 (skip) if it was already up to date.
_brew_ensure() {
  if command -v brew >/dev/null 2>&1; then
    local out; out="$(brew update 2>&1)"
    printf '%s' "$out" | grep -qi 'already up-to-date' && return 10
    return 0
  fi
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
  [ -x "$BREW_PREFIX/bin/brew" ] || command -v brew >/dev/null 2>&1
}
# Put brew on PATH for the rest of the run + future shells. Runs in the PARENT
# (right after the install task) so the change actually sticks. Idempotent.
_brew_shellenv() {
  BREW_PREFIX="$(brew --prefix 2>/dev/null || echo "$BREW_PREFIX")"
  eval "$("$BREW_PREFIX/bin/brew" shellenv 2>/dev/null)"
  grep -qsF '/brew shellenv' "$HOME/.zprofile" 2>/dev/null \
    || printf '\neval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX" >>"$HOME/.zprofile"
}

# ── Task model ───────────────────────────────────────────────────────────────
# Eight steps; each owns an ordered list of tasks. Tasks are flat parallel arrays
# so the renderer can group + count them per step.

# Clean categories. Homebrew is a real step (install + update), not a hidden wait.
# Each task is atomic — nothing is merged (git install and git config are separate).
STEP_ICON=(🍺 🐙 🧰 📦 🐚 🎨 🛒 🔄)
STEP_NAME=("Homebrew" "Git" "Formulae" "Casks" "Shell" "macOS Settings" "Mac App Store" "macOS Updates")
NSTEPS=${#STEP_NAME[@]}

T_STEP=(); T_LABEL=(); T_KIND=(); T_ARG=(); T_STAT=(); T_TIME=()
add_task() { T_STEP+=("$1"); T_LABEL+=("$2"); T_KIND+=("$3"); T_ARG+=("$4"); T_STAT+=("pending"); T_TIME+=(""); }

build_tasks() {
  local x id nm
  # 0 · Homebrew — the package manager itself (install if missing, else update)
  add_task 0 "package manager" homebrew ""
  # 1 · Git — install, then configure (separate tasks)
  add_task 1 "git" formula "git"
  add_task 1 "git config" fn _git_config
  # 2 · Formulae — taps first, then CLI tools / servers
  for x in "${TAPS[@]}"; do add_task 2 "tap ${x}" tap "$x"; done
  for x in "${FORMULAE[@]}"; do add_task 2 "$x" formula "$x"; done
  # 3 · Casks — apps
  for x in "${CASKS[@]}"; do add_task 3 "$x" cask "$x"; done
  # 4 · Shell — Oh My Zsh, then plugins/theme, then .zshrc
  add_task 4 "oh-my-zsh" omz ""
  for x in "${ZSH_PLUGINS[@]}"; do add_task 4 "${x%%|*}" plugin "$x"; done
  add_task 4 ".zshrc" fn _configure_zshrc
  # 5 · macOS Settings — appearance, then input, then system
  add_task 5 "Theme Mode" fn _appearance_prefs
  add_task 5 "App Icons" fn _appicons_prefs
  add_task 5 "Dock" fn _dock_prefs
  add_task 5 "Shortcuts" fn _keyboard_shortcut
  add_task 5 "Firewall" fn _firewall_on
  add_task 5 "Battery" fn _battery_prefs
  add_task 5 "Hostname" fn _hostname_set
  # 6 · Mac App Store
  for x in "${MAS_APPS[@]}"; do id="${x%%|*}"; nm="${x##*|}"; add_task 6 "$nm" mas "$id"; done
  # 7 · macOS Updates  (Command Line Tools + the macOS system, checked separately)
  add_task 7 "Command Line Tools" clt ""
  add_task 7 "macOS" macos ""
}

# Run one task (in a subshell). Exit code: 0 done · 10 skipped · 11 updated · else failed.
run_task() {
  local kind="${T_KIND[$1]}" arg="${T_ARG[$1]}"
  case "$kind" in
    homebrew) _brew_ensure; exit $? ;;
    fn)      "$arg"; exit $? ;;
    tap)     if brew tap 2>/dev/null | grep -qxF "$arg"; then brew trust --tap "$arg" >/dev/null 2>&1; exit 10; fi
             brew tap "$arg" || exit 1; brew trust --tap "$arg" >/dev/null 2>&1; exit 0 ;;
    formula) if ! brew list --formula --versions "$arg" >/dev/null 2>&1; then brew install "$arg" || exit 1; exit 0; fi
             [ -n "$(brew outdated --formula "$arg" 2>/dev/null)" ] && { brew upgrade --formula "$arg" || exit 1; exit 11; }; exit 10 ;;
    cask)    if ! brew list --cask --versions "$arg" >/dev/null 2>&1; then brew install --cask "$arg" || exit 1; exit 0; fi
             [ -n "$(brew outdated --cask "$arg" 2>/dev/null)" ] && { brew upgrade --cask "$arg" || exit 1; exit 11; }; exit 10 ;;
    omz)     [ -d "$HOME/.oh-my-zsh" ] && exit 10; _install_omz; exit $? ;;
    plugin)  local d="${arg#*|}"; d="${d%%|*}"; local u="${arg##*|}"
             [ -d "$HOME/.oh-my-zsh/custom/$d" ] && exit 10
             git clone --depth=1 "$u" "$HOME/.oh-my-zsh/custom/$d"; exit $? ;;
    mas)     mas list 2>/dev/null | grep -q "^$arg " && exit 10; mas install "$arg"; exit $? ;;
    clt)     softwareupdate -l >"$SU_CACHE" 2>&1   # one query to Apple, cached for the macOS task
             local lbl; lbl="$(grep 'Label:' "$SU_CACHE" 2>/dev/null | grep -i 'Command Line Tools' | sed -E 's/.*Label: *//; s/ *$//' | head -1)"
             [ -z "$lbl" ] && exit 10
             nohup sudo softwareupdate --download "$lbl" >/dev/null 2>&1 & exit 0 ;;
    macos)   local labels=() lbl
             while IFS= read -r lbl; do
               lbl="$(printf '%s' "$lbl" | sed -E 's/.*Label: *//; s/ *$//')"
               [ -n "$lbl" ] && labels+=("$lbl")
             done < <(grep 'Label:' "$SU_CACHE" 2>/dev/null | grep -vi 'Command Line Tools')
             [ "${#labels[@]}" -eq 0 ] && exit 10
             nohup sudo softwareupdate --download "${labels[@]}" >/dev/null 2>&1 & exit 0 ;;
  esac
  exit 0
}

_is_pkg() { case "$1" in formula|cask|omz|plugin|mas) return 0 ;; *) return 1 ;; esac; }

finish_task() {
  local i="$1" rc="$2" logf="$3" kind="${T_KIND[$1]}" label="${T_LABEL[$1]}"
  case "$rc" in
    0)  T_STAT[$i]="ok";   DONE=$((DONE + 1)); _is_pkg "$kind" && rec_installed "$label" ;;
    11) T_STAT[$i]="upd";  DONE=$((DONE + 1)); rec_updated "$label" ;;
    10) T_STAT[$i]="skip"; SKIPPED=$((SKIPPED + 1)); rec_skipped "$label" ;;
    *)  T_STAT[$i]="fail"; note_fail "$label"; { printf '\n=== %s ===\n' "$label"; cat "$logf"; } >>"$ERR_LOG" ;;
  esac
  case "$kind" in clt|macos) [ "$rc" = 0 ] && T_TIME[$i]="started" ;; esac   # background download kicked off
}

# ── Live full-screen view ────────────────────────────────────────────────────

ACTIVE_STEP=0; TFRAME=0; TASK_W=30
EOL=$'\033[K'   # clear to end of line, so a shrinking line leaves no stale tail

_step_counts() {   # echoes "total done" for step $1
  local s="$1" total=0 done=0 i
  for i in "${!T_STEP[@]}"; do
    [ "${T_STEP[$i]}" = "$s" ] || continue
    total=$((total + 1))
    case "${T_STAT[$i]}" in ok|skip|upd|fail) done=$((done + 1)) ;; esac
  done
  printf '%d %d' "$total" "$done"
}

render_task() {
  local i="$1" st="${T_STAT[$1]}" label="${T_LABEL[$1]}" tm="${T_TIME[$1]}" g gc sec sc="$MUTED"
  case "$st" in
    pending) g="○"; gc="$RULE";   sec="" ;;
    run)     g="${SPINNER[TFRAME % ${#SPINNER[@]}]}"; gc="$ACCENT"; sec="" ;;
    ok)      g="✓"; gc="$GREEN";  sec="$tm" ;;
    upd)     g="↑"; gc="$CYAN";   sec="${tm:-updated}" ;;
    skip)    g="⊘"; gc="$MUTED";  sec="skipped" ;;
    fail)    g="✗"; gc="$RED";    sec="failed"; sc="$RED" ;;
  esac
  printf '      %s%s%s  %-*s %s%s%s%s\n' "$gc" "$g" "$RESET" "$TASK_W" "$label" "$sc" "$sec" "$RESET" "$EOL"
}

# Every step is always expanded: a header (✓ done / ▸ in progress / ○ upcoming)
# plus all of its item rows, so the whole run is visible the entire time.
render_step() {
  local s="$1" badge="${CIRCLED[$s]}" icon="${STEP_ICON[$s]}" name="${STEP_NAME[$s]}"
  local cnt total done i hg hc; cnt="$(_step_counts "$s")"; total="${cnt% *}"; done="${cnt#* }"
  if [ "$total" -gt 0 ] && [ "$done" -ge "$total" ]; then hg="✓"; hc="$GREEN"
  elif [ "$s" -le "$ACTIVE_STEP" ]; then hg="▸"; hc="$ACCENT"
  else hg="○"; hc="$RULE"; fi
  printf '  %s%s%s %s %s  %s%s%s   %s%d/%d%s%s\n' \
    "$hc" "$hg" "$RESET" "$badge" "$icon" "$ACCENT$BOLD" "$name" "$RESET" "$MUTED" "$done" "$total" "$RESET" "$EOL"
  for i in "${!T_STEP[@]}"; do [ "${T_STEP[$i]}" = "$s" ] && render_task "$i"; done
}

render() {
  local td=0 tt="${#T_LABEL[@]}" pct=0 i s
  for i in "${!T_STAT[@]}"; do case "${T_STAT[$i]}" in ok|skip|upd|fail) td=$((td + 1)) ;; esac; done
  [ "$tt" -gt 0 ] && pct=$(( td * 100 / tt ))
  printf '\033[H'   # home (alt screen)
  printf '  %s%s❖  my-setup%s  %s· fresh macOS bootstrap%s%s\n%s\n' "$ACCENT" "$BOLD" "$RESET" "$MUTED" "$RESET" "$EOL" "$EOL"
  for s in $(seq 0 $((NSTEPS - 1))); do render_step "$s"; done
  printf '%s\n  %s%d%%%s  %s%d/%d tasks%s%s\n' \
    "$EOL" "$ACCENT$BOLD" "$pct" "$RESET" "$MUTED" "$td" "$tt" "$RESET" "$EOL"
  printf '\033[J'   # wipe anything left over from a taller previous frame
}

engine() {
  printf '\033[2J\033[H\033[?25l'; TUI_ACTIVE=1   # clear the screen, home, hide cursor
  local i pid rc t0 dt logf
  for i in "${!T_LABEL[@]}"; do
    ACTIVE_STEP="${T_STEP[$i]}"; T_STAT[$i]="run"
    logf="$(mktemp -t mysetup 2>/dev/null || echo "/tmp/mysetup.$$.$RANDOM")"; t0=$SECONDS
    ( run_task "$i" ) >"$logf" 2>&1 &
    pid=$!
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$((SECONDS - t0))" -ge "$STEP_TIMEOUT" ]; then
        printf '\n[my-setup] task exceeded %ss — terminated so the run can continue\n' "$STEP_TIMEOUT" >>"$logf"
        kill -TERM "$pid" 2>/dev/null; sleep 2; kill -KILL "$pid" 2>/dev/null; break
      fi
      render; TFRAME=$((TFRAME + 1)); sleep 0.1
    done
    { wait "$pid"; } 2>/dev/null; rc=$?
    [ "${T_KIND[$i]}" = "homebrew" ] && [ "$rc" -ne 1 ] && _brew_shellenv   # put brew on PATH (parent)
    dt=$((SECONDS - t0)); [ "$dt" -ge 1 ] && T_TIME[$i]="$(fmt_secs "$dt")"
    finish_task "$i" "$rc" "$logf"; rm -f "$logf"; render
  done
  ACTIVE_STEP=99; render
  printf '\033[?25h'; TUI_ACTIVE=0   # done: the final view stays put, cursor is freed
}

# Plain sequential output when there's no terminal (logs / CI).
stream() {
  local i rc t0 dt logf cur=-1
  for i in "${!T_LABEL[@]}"; do
    [ "${T_STEP[$i]}" != "$cur" ] && { cur="${T_STEP[$i]}"; printf '\n%s %s\n' "${CIRCLED[$cur]}" "${STEP_NAME[$cur]}"; }
    logf="$(mktemp -t mysetup 2>/dev/null || echo "/tmp/mysetup.$$.$RANDOM")"; t0=$SECONDS
    ( run_task "$i" ) >"$logf" 2>&1; rc=$?
    [ "${T_KIND[$i]}" = "homebrew" ] && [ "$rc" -ne 1 ] && _brew_shellenv
    dt=$((SECONDS - t0)); [ "$dt" -ge 1 ] && T_TIME[$i]="$(fmt_secs "$dt")"
    finish_task "$i" "$rc" "$logf"; rm -f "$logf"
    case "${T_STAT[$i]}" in
      ok)   printf '  + %s %s\n' "${T_LABEL[$i]}" "${T_TIME[$i]}" ;;
      upd)  printf '  ^ %s (updated)\n' "${T_LABEL[$i]}" ;;
      skip) printf '  . %s (skipped)\n' "${T_LABEL[$i]}" ;;
      fail) printf '  x %s (failed)\n' "${T_LABEL[$i]}" ;;
    esac
  done
}

# ── Summary ──────────────────────────────────────────────────────────────────

summary() {
  local upd; upd="$(_count "$RECAP_UPDATED")"
  printf '\n  %s%s❖  my-setup%s  %s· done in %s%s\n' "$ACCENT" "$BOLD" "$RESET" "$MUTED" "$(fmt_secs "$SECONDS")" "$RESET"
  printf '  %s%s✓ %d installed%s   %s↑ %d updated%s   %s⊘ %d skipped%s   %s✗ %d failed%s\n' \
    "$GREEN" "$BOLD" $((DONE - upd)) "$RESET" "$CYAN" "$upd" "$RESET" \
    "$MUTED" "$SKIPPED" "$RESET" "$RED" "$FAILED" "$RESET"
  if [ "$FAILED" -gt 0 ]; then
    printf '\n  %sFailures — re-run to retry (finished steps are skipped):%s\n' "$YELLOW" "$RESET"
    sed 's/^/    /' "$ERR_LOG"
  fi
  printf '\n'
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
  preflight
  printf '\n  %s%s❖  my-setup%s  %s· fresh macOS bootstrap%s\n\n' "$ACCENT" "$BOLD" "$RESET" "$MUTED" "$RESET"
  prime_sudo                      # one password prompt; Homebrew install is a step
  build_tasks
  if [ -t 1 ]; then engine; else stream; fi
  summary
}

main "$@"
