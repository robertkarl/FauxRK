#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tmp
work=$(mktemp -d "$PWD/build/tmp/session.XXXXXX")
export TMPDIR="$work"
export RK_TMUX_SOCKET="$work/tmux.sock"
trap 'tmux -S "$RK_TMUX_SOCKET" kill-server 2>/dev/null || true; rm -rf "$work"' EXIT
xcrun clang -fobjc-arc -ISources -framework Cocoa -framework ApplicationServices \
  Tests/session.m Sources/RKCore.m Sources/RKMonitor.m Sources/RKHelper.m Sources/RKPaneScreen.m -o "$work/session-test"
tmux -S "$RK_TMUX_SOCKET" -f /dev/null new-session -d -s fixture "$work/session-test" fixture
"$work/session-test"
