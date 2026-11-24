#!/bin/sh
# Run on the client Mac. Both the capture and the real agent use disposable
# one-pane sessions on the selected host's regular tmux server.
set -eu
if [ "$#" -ne 2 ]; then
    echo 'usage: Tests/live/debra.sh SSH_DESTINATION BUNDLED_HELPER_PATH' >&2
    exit 2
fi
host=$1
helper=$2
test -s "$helper"
cd "$(dirname "$0")/../.."
nonce=$(uuidgen | tr 'A-Z' 'a-z')
name=fauxrk-test-$nonce
work=build/remote/$name
mkdir -p "$work"
xcrun clang -arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -fmodules -Wall -I Sources \
    Tests/live/debra.m Sources/RKRemoteHost.m -framework Foundation -o "$work/client"
remote() { ssh -o BatchMode=yes -o ConnectTimeout=5 -- "$host" "$@"; }
scratch="Code/RK/$work"
remote "umask 077; mkdir -p '$scratch'; cat > '$scratch/input.py'" < Tests/live/debra-agent.py
cleanup() {
    remote /bin/sh -s -- "$nonce" <<'CLEAN'
set -eu
nonce=$1
tmux=/opt/homebrew/bin/tmux
# Match only the test-created pane option or the unique real spawn prompt.
owns="#{||:#{==:#{@fauxrk_test},$nonce},#{m:*FauxRK-$nonce*,#{pane_start_command}}}"
for pane in $("$tmux" list-panes -a -f "$owns" -F '#{pane_id}'); do
    "$tmux" if-shell -F -t "$pane" "$owns" "kill-pane -t $pane"
done
CLEAN
}
trap cleanup EXIT
pane=$(remote /bin/sh -s -- "$nonce" <<'SETUP'
set -eu
nonce=$1
work="$HOME/Code/RK/build/remote/fauxrk-test-$nonce"
name="fauxrk-test-$nonce"
/opt/homebrew/bin/tmux new-session -d -x 115 -y 38 -P -F '#{pane_id}' -s "$name" -c "$work" \
    '/usr/bin/python3 input.py' \; set-option -p -t "=$name:" @fauxrk_test "$nonce"
SETUP
)
"$work/client" "$host" "$helper" "$pane" "$nonce"
