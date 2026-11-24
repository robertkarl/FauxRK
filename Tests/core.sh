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
tm rename-window -t "$anchor" "Work Notes"
sibling=$(tm split-window -dP -F '#{pane_id}' -t "$anchor" /bin/cat)
client_count=$(tm list-clients | wc -l)
test "$client_count" -eq 0
"$scratch/core" unmanaged "$anchor"
occupied=$(tm new-session -dP -F '#{session_id}' -s 'source-Work Notes' /bin/cat)
session=$("$scratch/core" capture "$anchor")
test "$(tm display-message -p -t "$anchor" '#{session_name}')" = "source-Work Notes-2"
test "$(tm display-message -p -t "$anchor" '#{@rk_source_window}')" = "Work Notes"
test "$(tm display-message -p -t "$occupied" '#{session_name}')" = "source-Work Notes"
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
test "$(tm display-message -p -t "$sibling" '#{session_name}')" = source
# Literal format-looking text, punctuation, Unicode and command separators survive capture.
window_name="W:##{session_id}. #' Ω;"
other=$(tm new-session -dP -F '#{pane_id}' -s "Second" /bin/cat)
tm rename-session -t "$other" -- "Project ##{pane_id} Ω\;"
tm rename-window -t "$other" -- "${window_name%;}\;"
remaining=$(tm split-window -dP -F '#{pane_id}' -t "$other" /bin/cat)
"$scratch/core" capture "$other" >/dev/null
test "$(tm display-message -p -t "$other" '#{session_name}')" = "Project #{pane_id} Ω;-W_#{session_id}_ #' Ω;"
test "$(tm display-message -p -t "$other" '#{@rk_source_session}')" = 'Project #{pane_id} Ω;'
# A GUI-launched SSH helper may have no UTF-8 locale.
LC_ALL=C LANG=C "$scratch/core" capture "$remaining" >/dev/null
test "$(tm display-message -p -t "$remaining" '#{session_name}')" = 'Project #{pane_id} Ω;'
test "$(tm display-message -p -t "$other" '#{@rk_source_window}')" = "W:#{session_id}. #' Ω;"
tm rename-session -t "$other" -- "Renamed by me"
test "$("$scratch/core" label "$other")" = "Renamed by me"

# Each linked row points at the same pane but can have a different session name.
shared=$(tm new-session -dP -F '#{pane_id}' -s Zebra -n Shared /bin/cat)
legacy=$(tm split-window -dP -F '#{pane_id}' -t "$shared" /bin/cat)
survivor=$(tm split-window -dP -F '#{pane_id}' -t "$shared" /bin/cat)
alpha=$(tm new-session -dP -F '#{session_id}' -s Alpha /bin/cat)
zebra=$(tm display-message -p -t "$shared" '#{session_id}')
tm link-window -s "$zebra:0" -t "$alpha:1"
"$scratch/core" reject-session "$shared" "$occupied"
"$scratch/core" qualified "$shared" "$zebra" Zebra >/dev/null
test "$(tm display-message -p -t "$shared" '#{session_name}')" = 'Zebra-Shared'
"$scratch/core" capture "$legacy" >/dev/null
test "$(tm display-message -p -t "$legacy" '#{session_name}')" = 'Alpha-Shared'
test "$(tm list-panes -t "$alpha:1" -F '#{pane_id}')" = "$survivor"
test "$(tm list-panes -t "$zebra:0" -F '#{pane_id}')" = "$survivor"

slash=$(tm new-session -dP -F '#{pane_id}' -s 'Q\Code' -n 'W\file' /bin/cat)
last=$(tm split-window -dP -F '#{pane_id}' -t "$slash" /bin/cat)
source_name=$(tm display-message -p -t "$last" '#{session_name}')
source_window=$(tm display-message -p -t "$last" '#{window_name}')
"$scratch/core" capture "$slash" >/dev/null
test "$(tm display-message -p -t "$slash" '#{session_name}')" = "$source_name-W\\\\file"
"$scratch/core" capture "$last" >/dev/null
test "$(tm display-message -p -t "$last" '#{session_name}')" = "$source_name"
test "$(tm display-message -p -t "$last" '#{window_name}')" = "$source_window"
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
