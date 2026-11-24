#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tmp
scratch=$(mktemp -d "$PWD/build/tmp/host.XXXXXX")
export TMPDIR="$scratch"
export RK_TMUX_SOCKET="$scratch/s"
export RK_HOST_FIXTURE="$scratch"
export ZDOTDIR="$scratch"
export RK_HOST_FIXTURE_SUITE="net.robertkarl.FauxRK.Tests.$(uuidgen)"
export CFFIXED_USER_HOME="$scratch/home"
mkdir -p "$scratch/bin" "$CFFIXED_USER_HOME/Code/regina" "$CFFIXED_USER_HOME/homelab" "$CFFIXED_USER_HOME/Code/unbiasedbob-private"
cat > "$scratch/bin/claude" <<'PYTHON'
#!/usr/bin/env python3
import json, os, signal, sys, time
from pathlib import Path
if sys.argv[1:] == ["app-server","daemon","start"]: sys.exit(0)
Path("invocation.json").write_text(json.dumps({"cwd":os.getcwd(),"args":sys.argv[1:]}))
signal.signal(signal.SIGINT, lambda *_: Path("interrupted").touch())
while True: time.sleep(1)
PYTHON
chmod +x "$scratch/bin/claude"
ln -s claude "$scratch/bin/codex"
trap 'defaults delete "$RK_HOST_FIXTURE_SUITE" >/dev/null 2>&1 || true; tmux -S "$RK_TMUX_SOCKET" kill-server >/dev/null 2>&1 || true; rm -rf "$scratch"' EXIT
cat > "$ZDOTDIR/.zshrc" <<'ZSH'
export PATH="$RK_HOST_FIXTURE/bin:$PATH"
alias claudesonnet='rk_preview'
rk_preview() {
  : > "$RK_HOST_FIXTURE/preview-started"
  while [[ ! -f "$RK_HOST_FIXTURE/release-preview" ]]; do /bin/sleep .05; done
  /bin/cat >/dev/null
  print -r -- '{"state":"input","summary":"The isolated fixture wants an answer.","question":"Continue? [y/N]"}'
}
ZSH
xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Wno-unused-parameter -ISources "-DRK_SSH_HANDOFF_SUITE=@\"$RK_HOST_FIXTURE_SUITE\"" \
    -framework Cocoa -framework ApplicationServices Helper/main.m Sources/RKLocalHost.m Sources/RKCore.m \
    Sources/RKMonitor.m Sources/RKPaneScreen.m Sources/RKHelper.m Sources/RKRemoteTerminal.m -o "$scratch/host-fixture"
python3 Tests/host_protocol.py "$scratch/host-fixture" "$scratch"
