#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tmp
work=$(mktemp -d "$PWD/build/tmp/terminal.XXXXXX")
export RK_TERMINAL_WORK="$work"
export RK_TMUX_SOCKET="$work/tmux.sock"
trap 'tmux -S "$RK_TMUX_SOCKET" kill-server 2>/dev/null || true; rm -rf "$work"' EXIT
tmux=/opt/homebrew/bin/tmux
[ -x "$tmux" ] || tmux=$(command -v tmux)
# Stands in for the remote tmux on the default socket.
printf '#!/bin/sh\nexec %s -S %s "$@"\n' "$tmux" "$RK_TMUX_SOCKET" > "$work/tmuxw"
# Stands in for ssh: records its arguments, then runs the command as a remote login shell would.
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > %s/ssh-args\nshift 3\nexec /bin/sh -c "$1"\n' "$work" > "$work/fakessh"
chmod +x "$work/tmuxw" "$work/fakessh"
xcrun clang -fobjc-arc -ISources -framework Cocoa -framework ApplicationServices \
  Tests/terminal.m Sources/RKRemoteTerminal.m Sources/RKCore.m Sources/RKMonitor.m Sources/RKHelper.m Sources/RKPaneScreen.m -o "$work/terminal-test"
"$work/terminal-test"
