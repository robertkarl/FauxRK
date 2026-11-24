#!/bin/bash
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
mkdir -p build/tmp
scratch=$(mktemp -d "$PWD/build/tmp/core.XXXXXX")
export TMPDIR="$scratch"
export RK_TMUX_SOCKET="$scratch/test.sock"
export RK_TEST_WORKSPACE="$scratch/project #1"
mkdir -p "$RK_TEST_WORKSPACE"
tm() { tmux -S "$RK_TMUX_SOCKET" "$@"; }
trap 'tm kill-server 2>/dev/null || true; rm -rf "$scratch"' EXIT
clang -Wall -Wextra -Werror -fobjc-arc -framework AppKit -framework ApplicationServices Sources/RKCore.m Tests/core.m -o "$scratch/core"
# A deterministic substitute reads CLI argv and stays interactive. No provider
# requests, account state, or commands on any normal tmux server are involved.
export ZDOTDIR="$scratch"
cat > "$scratch/.zshrc" <<'ZSH'
export PATH="$ZDOTDIR:$PATH"
ZSH
cat > "$scratch/codex" <<'SH'
#!/bin/sh
if [ "$*" = "app-server daemon start" ]; then
    touch "$PWD/daemon-ready"
    exit 0
fi
[ -f "$PWD/daemon-ready" ] || exit 1
printf '%s\0' "$@" > "$PWD/argv"
exec /bin/cat
SH
chmod +x "$scratch/codex"
anchor=$(tm -f /dev/null new-session -dP -F '#{pane_id}' -s 'source' -c "$RK_TEST_WORKSPACE" /bin/cat)
sibling=$(tm split-window -dP -F '#{pane_id}' -t "$anchor" /bin/cat)
client_count=$(tm list-clients | wc -l)
test "$client_count" -eq 0
"$scratch/core" unmanaged "$anchor"
session=$("$scratch/core" capture "$anchor")
test "$(tm list-panes -t "$session" -F '#{pane_id}')" = "$anchor"
test "$(tm list-panes -t source -F '#{pane_id}')" = "$sibling"
"$scratch/core" stale "$anchor"
"$scratch/core" send "$anchor"
tm capture-pane -pt "$anchor" | grep -Fq -- "-- literal ' and ; \$(touch BAD)"
tm capture-pane -pt "$anchor" | grep -Fq 'next line'
test ! -e "$RK_TEST_WORKSPACE/BAD"
extra=$(tm new-window -dP -F '#{pane_id}' -t "$session" /bin/cat)
"$scratch/core" siblings "$anchor"
tm kill-pane -t "$extra"
"$scratch/core" end "$anchor"
tm has-session -t source
singleton=$("$scratch/core" capture "$sibling")
test "$(tm list-panes -t "$singleton" -F '#{pane_id}')" = "$sibling"
! tm has-session -t source 2>/dev/null
pid=$("$scratch/core" spawn unused)
for _ in {1..50}; do [ -f "$RK_TEST_WORKSPACE/argv" ] && break; sleep .1; done
python3 - "$RK_TEST_WORKSPACE/argv" <<'PY'
import sys
from pathlib import Path
args = Path(sys.argv[1]).read_bytes().split(b'\0')[:-1]
assert [x.decode() for x in args] == ["--remote", "unix://", "-m", "gpt-6.2-astra", "-c", "model_reasoning_effort=medium", "--", "--hello\n$(touch BAD); #{pane_id} 'quote' 💬"], args
PY
test ! -e "$RK_TEST_WORKSPACE/BAD"
"$scratch/core" end "$pid"
shellpane=$(tm new-session -dP -F '#{pane_id}' -s shell /bin/sh)
"$scratch/core" capture "$shellpane" >/dev/null
"$scratch/core" shell "$shellpane"
echo "tmux core passed (detached spawn, capture, literal input, identity and ownership guards, end)"
