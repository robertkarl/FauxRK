#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tmp
scratch=$(mktemp -d "$PWD/build/tmp/host.XXXXXX")
export TMPDIR="$scratch"
export RK_TMUX_SOCKET="$scratch/s"
export RK_HOST_FIXTURE="$scratch"
export ZDOTDIR="$scratch"
trap 'tmux -S "$RK_TMUX_SOCKET" kill-server >/dev/null 2>&1 || true; rm -rf "$scratch"' EXIT
cat > "$ZDOTDIR/.zshrc" <<'ZSH'
alias claudesonnet='rk_preview'
rk_preview() {
  : > "$RK_HOST_FIXTURE/preview-started"
  while [[ ! -f "$RK_HOST_FIXTURE/release-preview" ]]; do /bin/sleep .05; done
  /bin/cat >/dev/null
  print -r -- '{"state":"input","summary":"The isolated fixture wants an answer.","question":"Continue? [y/N]"}'
}
ZSH
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -ISources \
    -framework Cocoa -framework ApplicationServices Helper/main.m Sources/RKLocalHost.m Sources/RKCore.m \
    Sources/RKMonitor.m Sources/RKPaneScreen.m Sources/RKHelper.m Sources/RKRemoteTerminal.m -o "$scratch/host-fixture"
python3 Tests/host_protocol.py "$scratch/host-fixture" "$scratch"
