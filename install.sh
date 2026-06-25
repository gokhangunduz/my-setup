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
  mas
)

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

# Mac App Store apps via `mas`: "app-id|name". Sign into the App Store first.
MAS_APPS=(
  "497799835|Xcode"
  "310633997|WhatsApp"
  "640199958|Apple Developer"
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

INSTALLED=0; UPDATED=0; SKIPPED=0; FAILED=0
ERR_LOG="$(mktemp -t mysetup-errors 2>/dev/null || echo /tmp/mysetup-errors.$$)"
SU_CACHE="$(mktemp -t mysetup-swupdate 2>/dev/null || echo /tmp/mysetup-swupdate.$$)"
SUDO_KEEPALIVE_PID=""; SUDO_PRIMED=0
SUDOERS_FILE="/etc/sudoers.d/my-setup"; SUDOERS_INSTALLED=0
STEP_TIMEOUT=1800   # seconds: kill any task that hangs longer, then continue
TUI_ACTIVE=0
SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
CIRCLED=(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩)

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
  [ "$SUDO_PRIMED" = "1" ] && sudo -k 2>/dev/null
  rm -f "$ERR_LOG" "$SU_CACHE" 2>/dev/null
}
trap cleanup EXIT INT TERM

fmt_secs() { local s=$1; if [ "$s" -lt 60 ]; then printf '%ds' "$s"; else printf '%dm%02ds' $((s / 60)) $((s % 60)); fi; }

# ── Commands the tasks run ───────────────────────────────────────────────────
# Each returns 10 when already in the desired state (shown as ⊘ skipped).

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

_configure_zsh_plugins() {
  local f="$HOME/.zsh_plugins.txt" tmp; tmp="$(mktemp)"
  printf '%s\n' "${ZSH_PLUGINS[@]}" >"$tmp"
  if [ -f "$f" ] && cmp -s "$tmp" "$f"; then rm -f "$tmp"; return 10; fi
  mv "$tmp" "$f"
}

# Fenced block in ~/.zshrc so we never clobber the user's lines. Markers must stay
# free of regex-special characters (they're used as awk patterns below).
_ZRC_BEGIN="# my-setup antidote begin"
_ZRC_END="# my-setup antidote end"
_zshrc_block() {
  cat <<'BLK'
# my-setup antidote begin
# Powerlevel10k instant prompt — keep this near the top.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
# antidote — clones and loads every plugin listed in ~/.zsh_plugins.txt
for _ad in "${HOMEBREW_PREFIX:-/opt/homebrew}" /opt/homebrew /usr/local; do
  [[ -r "$_ad/share/antidote/antidote.zsh" ]] && { source "$_ad/share/antidote/antidote.zsh"; break; }
done
unset _ad
antidote load
autoload -Uz compinit && compinit -u
[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
# my-setup antidote end
BLK
}

_configure_zshrc() {
  local rc="$HOME/.zshrc"; [ -f "$rc" ] || touch "$rc"
  local wantf curf tmp; wantf="$(mktemp)"; curf="$(mktemp)"
  _zshrc_block >"$wantf"
  awk -v b="$_ZRC_BEGIN" -v e="$_ZRC_END" '$0 ~ b {f=1} f {print} $0 ~ e {f=0}' "$rc" >"$curf"
  if cmp -s "$wantf" "$curf"; then rm -f "$wantf" "$curf"; return 10; fi
  tmp="$(mktemp)"
  awk -v b="$_ZRC_BEGIN" -v e="$_ZRC_END" '$0 ~ b {skip=1} skip!=1 {print} $0 ~ e {skip=0}' "$rc" >"$tmp"
  printf '\n' >>"$tmp"; cat "$wantf" >>"$tmp"
  mv "$tmp" "$rc"; rm -f "$wantf" "$curf"
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
# Cmd+" → "Move focus to next window" (hotkey 27). params = (34=", 10=key code on
# this layout, 1048576=Cmd), captured from System Settings; re-capture if it differs.
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
  local cust bat ac
  cust="$(pmset -g custom 2>/dev/null)"
  bat="$(printf '%s' "$cust" | sed -n '/Battery/,/AC Power/p')"   # battery section
  ac="$(printf '%s' "$cust" | sed -n '/AC Power/,$p')"            # power-adapter section
  printf '%s' "$bat" | grep -qE 'lessbright[[:space:]]+1' \
    && printf '%s' "$bat" | grep -qE 'womp[[:space:]]+0' \
    && printf '%s' "$ac" | grep -qE '[^a-z]sleep[[:space:]]+0' \
    && printf '%s' "$ac" | grep -qE 'womp[[:space:]]+1' && return 10
  sudo pmset -b lessbright 1 &&   # dim on battery
  sudo pmset -c sleep 0 &&        # never auto-sleep on AC
  sudo pmset -c womp 1 &&         # wake for network on AC
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

# One password prompt, then a temporary passwordless-sudo rule (revoked on exit).
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

# Homebrew: install if missing, else update; return 10 if already up to date.
_brew_ensure() {
  if command -v brew >/dev/null 2>&1; then
    local out; out="$(brew update 2>&1)"
    printf '%s' "$out" | grep -qi 'already up-to-date' && return 10
    return 0
  fi
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
  [ -x "$BREW_PREFIX/bin/brew" ] || command -v brew >/dev/null 2>&1
}
# Put brew on PATH for the rest of the run + future shells. Runs in the PARENT.
_brew_shellenv() {
  BREW_PREFIX="$(brew --prefix 2>/dev/null || echo "$BREW_PREFIX")"
  eval "$("$BREW_PREFIX/bin/brew" shellenv 2>/dev/null)"
  grep -qsF '/brew shellenv' "$HOME/.zprofile" 2>/dev/null \
    || printf '\neval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX" >>"$HOME/.zprofile"
}

# ── Task model ───────────────────────────────────────────────────────────────
# Eight steps; tasks are flat parallel arrays so the renderer can group/count them.

STEP_ICON=(🍺 🐙 🧰 📦 🐚 🎨 🛒 🔄)
STEP_NAME=("Homebrew" "Git" "Formulae" "Casks" "Shell" "macOS Settings" "Mac App Store" "macOS Updates")
NSTEPS=${#STEP_NAME[@]}

T_STEP=(); T_LABEL=(); T_KIND=(); T_ARG=(); T_STAT=(); T_TIME=()
add_task() { T_STEP+=("$1"); T_LABEL+=("$2"); T_KIND+=("$3"); T_ARG+=("$4"); T_STAT+=("pending"); T_TIME+=(""); }

build_tasks() {
  local x id nm
  # 0 · Homebrew
  add_task 0 "package manager" homebrew ""
  # 1 · Git (install + config, separate tasks)
  add_task 1 "git" formula "git"
  add_task 1 "git config" fn _git_config
  # 2 · Formulae (taps first)
  for x in "${TAPS[@]}"; do add_task 2 "tap ${x}" tap "$x"; done
  for x in "${FORMULAE[@]}"; do add_task 2 "$x" formula "$x"; done
  # 3 · Casks
  for x in "${CASKS[@]}"; do add_task 3 "$x" cask "$x"; done
  # 4 · Shell (antidote plugin list + .zshrc)
  add_task 4 ".zsh_plugins.txt" fn _configure_zsh_plugins
  add_task 4 ".zshrc" fn _configure_zshrc
  # 5 · macOS Settings
  add_task 5 "Theme Mode" fn _appearance_prefs
  add_task 5 "App Icons" fn _appicons_prefs
  add_task 5 "Dock" fn _dock_prefs
  add_task 5 "Shortcuts" fn _keyboard_shortcut
  add_task 5 "Firewall" fn _firewall_on
  add_task 5 "Battery" fn _battery_prefs
  add_task 5 "Hostname" fn _hostname_set
  # 6 · Mac App Store
  for x in "${MAS_APPS[@]}"; do id="${x%%|*}"; nm="${x##*|}"; add_task 6 "$nm" mas "$id"; done
  # 7 · macOS Updates (CLT + macOS, checked separately)
  add_task 7 "Command Line Tools" clt ""
  add_task 7 "macOS" macos ""
}

# Install $2 (--formula/--cask) if missing, upgrade if outdated, else leave it.
# exit 0 installed · 11 upgraded · 10 current.
_brew_pkg() {
  brew list "$1" --versions "$2" >/dev/null 2>&1 || { brew install "$1" "$2" || exit 1; exit 0; }
  [ -n "$(brew outdated "$1" "$2" 2>/dev/null)" ] && { brew upgrade "$1" "$2" || exit 1; exit 11; }
  exit 10
}

# Run one task (in a subshell). Exit code: 0 done · 10 skipped · 11 updated · else failed.
run_task() {
  local kind="${T_KIND[$1]}" arg="${T_ARG[$1]}"
  case "$kind" in
    homebrew) _brew_ensure; exit $? ;;
    fn)      "$arg"; exit $? ;;
    tap)     if brew tap 2>/dev/null | grep -qxF "$arg"; then brew trust --tap "$arg" >/dev/null 2>&1; exit 10; fi
             brew tap "$arg" || exit 1; brew trust --tap "$arg" >/dev/null 2>&1; exit 0 ;;
    formula) _brew_pkg --formula "$arg" ;;
    cask)    _brew_pkg --cask "$arg" ;;
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

finish_task() {
  local i="$1" rc="$2" logf="$3" kind="${T_KIND[$1]}" label="${T_LABEL[$1]}"
  case "$rc" in
    0)  T_STAT[$i]="ok";   INSTALLED=$((INSTALLED + 1)) ;;
    11) T_STAT[$i]="upd";  UPDATED=$((UPDATED + 1)) ;;
    10) T_STAT[$i]="skip"; SKIPPED=$((SKIPPED + 1)) ;;
    *)  T_STAT[$i]="fail"; FAILED=$((FAILED + 1)); { printf '\n=== %s ===\n' "$label"; cat "$logf"; } >>"$ERR_LOG" ;;
  esac
  case "$kind" in clt|macos) [ "$rc" = 0 ] && T_TIME[$i]="started" ;; esac
}

# ── Live full-screen view ────────────────────────────────────────────────────

ACTIVE_STEP=0; TFRAME=0; TASK_W=30
EOL=$'\033[K'   # clear to EOL so a shrinking line leaves no stale tail

_step_counts() {
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

# Every step stays expanded: header (✓ done / ▸ active / ○ upcoming) + all its rows.
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
  printf '\033[H'
  printf '  %s%s❖  my-setup%s  %s· fresh macOS bootstrap%s%s\n%s\n' "$ACCENT" "$BOLD" "$RESET" "$MUTED" "$RESET" "$EOL" "$EOL"
  for s in $(seq 0 $((NSTEPS - 1))); do render_step "$s"; done
  printf '%s\n  %s%d%%%s  %s%d/%d tasks%s%s\n' \
    "$EOL" "$ACCENT$BOLD" "$pct" "$RESET" "$MUTED" "$td" "$tt" "$RESET" "$EOL"
  printf '\033[J'
}

_new_logf() { mktemp -t mysetup 2>/dev/null || echo "/tmp/mysetup.$$.$RANDOM"; }

# Post-task bookkeeping shared by engine + stream: put brew on PATH after the
# Homebrew step (parent side), record elapsed time, tally the result, drop the log.
_finish_one() {
  local i="$1" rc="$2" logf="$3" t0="$4" dt
  [ "${T_KIND[$i]}" = "homebrew" ] && [ "$rc" -ne 1 ] && _brew_shellenv
  dt=$((SECONDS - t0)); [ "$dt" -ge 1 ] && T_TIME[$i]="$(fmt_secs "$dt")"
  finish_task "$i" "$rc" "$logf"; rm -f "$logf"
}

engine() {
  printf '\033[2J\033[H\033[?25l'; TUI_ACTIVE=1
  local i pid rc t0 logf
  for i in "${!T_LABEL[@]}"; do
    ACTIVE_STEP="${T_STEP[$i]}"; T_STAT[$i]="run"
    logf="$(_new_logf)"; t0=$SECONDS
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
    _finish_one "$i" "$rc" "$logf" "$t0"; render
  done
  ACTIVE_STEP=99; render
  printf '\033[?25h'; TUI_ACTIVE=0
}

# Plain sequential output when there's no terminal (logs / CI).
stream() {
  local i rc t0 logf cur=-1
  for i in "${!T_LABEL[@]}"; do
    [ "${T_STEP[$i]}" != "$cur" ] && { cur="${T_STEP[$i]}"; printf '\n%s %s\n' "${CIRCLED[$cur]}" "${STEP_NAME[$cur]}"; }
    logf="$(_new_logf)"; t0=$SECONDS
    ( run_task "$i" ) >"$logf" 2>&1; rc=$?
    _finish_one "$i" "$rc" "$logf" "$t0"
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
  printf '\n  %s%s❖  my-setup%s  %s· done in %s%s\n' "$ACCENT" "$BOLD" "$RESET" "$MUTED" "$(fmt_secs "$SECONDS")" "$RESET"
  printf '  %s%s✓ %d installed%s   %s↑ %d updated%s   %s⊘ %d skipped%s   %s✗ %d failed%s\n' \
    "$GREEN" "$BOLD" "$INSTALLED" "$RESET" "$CYAN" "$UPDATED" "$RESET" \
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
  prime_sudo
  build_tasks
  if [ -t 1 ]; then engine; else stream; fi
  summary
}

main "$@"
