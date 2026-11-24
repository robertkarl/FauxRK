#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/tmp
scratch=$(mktemp -d "$PWD/build/tmp/transport.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
export TMPDIR="$scratch"
export RK_FIXTURE_ACCOUNT="$scratch/account with spaces"
export RK_FIXTURE_SSH="$scratch/ssh"
mkdir -p "$RK_FIXTURE_ACCOUNT"
# The shim executes the actual remote shell bootstrap in a private fixture
# directory. Only the bootstrap's remote home path changes.
cat > "$RK_FIXTURE_SSH" <<'PY'
#!/usr/bin/python3
import os, shlex, sys
from pathlib import Path
args = sys.argv[1:]
assert args[-3:-1] == ["--", "test@Debra"]
assert "-T" in args and "BatchMode=yes" in args and "StrictHostKeyChecking=yes" in args
account = Path(os.environ["RK_FIXTURE_ACCOUNT"])
with (account / "connections").open("a") as log:
    log.write("connected\n")
entry = shlex.split(args[-1])
assert entry[:3] == ["exec", "/bin/sh", "-c"]
script = entry[3].replace("$HOME/Library/", "$RK_FIXTURE_ACCOUNT/Library/")
os.execl("/bin/sh", "sh", "-c", script)
PY
cat > "$RK_FIXTURE_ACCOUNT/helper-v1" <<'PY'
#!/usr/bin/python3
from pathlib import Path
import json, os, sys, threading, time
base = Path(os.environ["RK_FIXTURE_ACCOUNT"])
lock = threading.Lock()
def reply(item, **result):
    with lock:
        print(json.dumps(dict(id=item["id"], **result)), flush=True)
def preview(item):
    (base / "preview-started").touch()
    while not (base / "finish-preview").exists(): time.sleep(.01)
    reply(item, value="preview complete")
for line in sys.stdin:
    item = json.loads(line)
    op = item["op"]
    if op == "snapshot": reply(item, value=dict(ok=True, pid=os.getpid()))
    elif op == "preview": threading.Thread(target=preview, args=(item,), daemon=True).start()
    elif op == "rejected": reply(item, error="pane moved")
    elif op == "echo": reply(item, value=item["args"]["text"])
    elif op == "steer":
        with (base / "sent").open("a") as log: log.write("once\n")
        os._exit(7)
    elif op == "hang": time.sleep(10)
PY
cp "$RK_FIXTURE_ACCOUNT/helper-v1" "$RK_FIXTURE_ACCOUNT/helper-v2"
echo '# Version 2' >> "$RK_FIXTURE_ACCOUNT/helper-v2"
chmod +x "$RK_FIXTURE_SSH"
xcrun clang -fobjc-arc -Wall -Wextra -Werror -I Sources -framework Foundation Tests/transport.m Sources/RKRemoteHost.m -o "$scratch/test"
"$scratch/test"
