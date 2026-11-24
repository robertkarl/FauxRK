#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d -t rk-monitor-test)
# Alias fixtures create their own tmux server, including when running inside the user's tmux.
export RK_TMUX_SOCKET="rk-monitor-test-$(uuidgen)"
trap 'tmux -L "$RK_TMUX_SOCKET" kill-server >/dev/null 2>&1 || true; rm -rf "$work"' EXIT
xcrun clang -fobjc-arc -framework Cocoa Sources/RKCore.m Sources/RKPaneScreen.m Sources/RKHelper.m Sources/RKMonitor.m Tests/monitor.m -o "$work/tests"
"$work/tests"

mkdir "$work/zsh"
cat > "$work/zsh/.zshrc" <<'ZSH'
alias claudesonnet='rk_fixture_helper'
rk_fixture_helper() {
  [[ -n "$TMUX" && -n "$TMUX_PANE" ]] || return 3
  info=$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}|#{window_id}|#{@rk_helper}|#{@rk_managed}')
  print -r -- "$info" >> "$RK_HELPER_FIXTURE_LOG"
  /bin/cat >/dev/null
  print -r -- '{"state":"input","question":"Install the dependency?","summary":"Fixture alias saw this new tmux window."}'
}
ZSH
# A keeper session allows verifying helper cleanup and window ID uniqueness across calls.
export ZDOTDIR="$work/zsh"
export RK_HELPER_FIXTURE_LOG="$work/calls"
tmux -L "$RK_TMUX_SOCKET" -f /dev/null new-session -d -s fixture-keeper 'sleep 120'
"$work/tests" sonnet
"$work/tests" sonnet
awk -F '|' '$1 ~ /^rk-helpers-/ && $2 ~ /^@[0-9]+$/ && $3 == "1" && $4 == "" { windows[$2]=1; n++ } END { exit !(n==2 && length(windows)==2) }' "$work/calls"
test "$(tmux -L "$RK_TMUX_SOCKET" list-sessions -F '#{session_name}')" = fixture-keeper

if [ "${RK_TEST_LIVE_SONNET:-0}" = 1 ]; then
  # A fresh server must load the actual user's zsh environment.
  tmux -L "$RK_TMUX_SOCKET" kill-server
  unset ZDOTDIR RK_HELPER_FIXTURE_LOG
  "$work/tests" sonnet
fi
