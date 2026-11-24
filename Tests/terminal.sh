#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
work=$(mktemp -d "$PWD/build/t.XXXXXX")
export RK_TERMINAL_WORK="$work"
# Quotes and shell metacharacters are literal characters in this socket's filename.
export RK_TMUX_SOCKET="$work/s 'x;\$(q)"
trap 'tmux -S "$RK_TMUX_SOCKET" kill-server 2>/dev/null || true; rm -rf "$work"' EXIT
# Stands in for ssh: records its arguments, then runs the command as a remote login shell would.
printf '#!/bin/sh\nprintf "%%s\\n" "$@" > %s/ssh-args\nshift 7\nexec /bin/sh -c "$1"\n' "$work" > "$work/fakessh"
chmod +x "$work/fakessh"
xcrun clang -fobjc-arc -ISources -framework Cocoa -framework ApplicationServices \
  Tests/terminal.m Sources/RKRemoteTerminal.m Sources/RKCore.m Sources/RKMonitor.m Sources/RKHelper.m Sources/RKPaneScreen.m -o "$work/terminal-test"
"$work/terminal-test"
