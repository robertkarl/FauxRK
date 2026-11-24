"""Exercise the real JSONL helper against a private tmux server and a terminal fixture."""

import json
import os
from pathlib import Path
import select
import subprocess
import sys
import time
import uuid

binary = Path(sys.argv[1])
work = Path(sys.argv[2])
socket = os.environ["RK_TMUX_SOCKET"]


def tmux(*args):
    return subprocess.check_output(["tmux", "-S", socket, *args], text=True).strip()


class Host:
    def __init__(self):
        self.proc = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)

    def write(self, data):
        self.proc.stdin.write(data)

    def send(self, op, **args):
        request_id = str(uuid.uuid4())
        request = {"id": request_id, "op": op, "args": args}
        self.write(json.dumps(request).encode() + b"\n")
        return request_id

    def receive(self):
        assert select.select([self.proc.stdout], [], [], 8)[0], "Helper response timed out"
        message = self.proc.stdout.readline()
        assert message, "Helper closed its response stream unexpectedly"
        return json.loads(message)

    def run(self, op, expect_error=False, **args):
        request_id = self.send(op, **args)
        response = self.receive()
        assert response["id"] == request_id, response
        if expect_error:
            assert isinstance(response.get("error"), str) and "value" not in response, response
            return response["error"]
        assert "value" in response and "error" not in response, response
        return response["value"]

    def close(self):
        self.proc.stdin.close()
        assert self.proc.wait(timeout=4) == 0
        self.proc.stdout.close()


script = work / "agent.py"
script.write_text("""import pathlib, sys, time
root = pathlib.Path(sys.argv[1])
answer = input('Continue? [y/N] ')
(root/'answer').write_text(answer)
print('All fixture checks passed.\\n›', flush=True)
while True: time.sleep(1)
""")
pane_id = tmux("-f", "/dev/null", "new-session", "-dP", "-F", "#{pane_id}", "-s", "source", sys.executable, "-u", str(script), str(work))
sibling = tmux("split-window", "-dP", "-F", "#{pane_id}", "-t", pane_id, "/bin/cat")
assert tmux("list-clients") == ""
host = Host()
host.write(b"[]\n")
assert host.receive()["id"] is None
host.write(b'{"id":12,"args":{},"op":"snapshot"}\n')
assert "error" in host.receive()
assert host.run("system", expect_error=True)
assert host.run("end", expect_error=True, target=pane_id)
assert host.run("snapshot", expect_error=True, provider="unknown")
assert host.run("snapshot", expect_error=True, unexpected=True)
assert host.run("spawn", expect_error=True, preset="Opus", directory=str(work), prompt="")
assert host.run("spawn", expect_error=True, preset="Opus", directory="~/Code/regina/../", prompt="")
assert "preset" in host.run("spawn", expect_error=True, preset="unrecognized", directory="~/Code/regina/")

# The helper remains usable after a malformed or oversized record.
host.write(b"x" * (4 * 1024 * 1024 + 20) + b"\n")
assert "error" in host.receive()
snap = host.run("snapshot", provider="sonnet", model="qwen3:4b", focusToken="")
source = next(p for p in snap["panes"] if p["id"] == pane_id)
assert not source["managed"] and not source["focused"]
assert not snap["attention"]
raw = source["target"]

# A blocked preview never holds up snapshot or control traffic.
preview_id = host.send("preview", target=raw)
deadline = time.monotonic() + 5
while not (work / "preview-started").exists() and time.monotonic() < deadline:
    time.sleep(.03)
assert (work / "preview-started").is_file()
host.run("snapshot", provider="sonnet", model="qwen3:4b", focusToken="")
(work / "release-preview").touch()
assert host.receive() == {"id": preview_id, "value": "The isolated fixture wants an answer."}

assert host.run("capture", target=raw) is True
snap = host.run("snapshot")
owned = next(p for p in snap["panes"] if p["id"] == pane_id)
assert owned["managed"] and owned["target"] != raw and owned["rkID"]
assert not next(p["managed"] for p in snap["panes"] if p["id"] == sibling)
target = owned["target"]
assert host.run("end", expect_error=True, target=raw)
assert host.run("open", expect_error=True, target=target)
assert host.run("attach", expect_error=True, target=raw)
attachment = host.run("attach", target=target)
assert attachment["sessionID"] == owned["sessionID"] and Path(attachment["binary"]).is_absolute()

row = snap["attention"][pane_id]
assert row["kind"] == "input" and row["choiceSource"] == "terminal", row
assert host.run("steer", expect_error=True, target=target, text="Do another task")
assert host.run("answer", expect_error=True, id=pane_id, fingerprint="old", choice=row["choices"][1])
assert host.run("answer", expect_error=True, id=pane_id, fingerprint=row["fingerprint"], choice={"draft": {}, "text": "unsent", "label": "Reply"})
assert not (work / "answer").exists()
assert host.run("answer", id=pane_id, fingerprint=row["fingerprint"], choice=row["choices"][1])
deadline = time.monotonic() + 3
while not (work / "answer").exists() and time.monotonic() < deadline:
    time.sleep(.03)
assert (work / "answer").read_text() == "n"
result = host.run("snapshot")["attention"][pane_id]
assert result["kind"] == "complete", result
assert host.run("read", id=pane_id, fingerprint=result["fingerprint"])
assert not host.run("snapshot")["attention"]

# Half-written commands are never accepted on EOF. The tmux agent survives disconnect.
partial = {"id": "incomplete", "op": "end", "args": {"target": target}}
host.write(json.dumps(partial).encode())
host.close()
assert tmux("display-message", "-p", "-t", pane_id, "#{pane_id}") == pane_id
host = Host()
restored = host.run("snapshot")
assert any(p["rkID"] == owned["rkID"] for p in restored["panes"])
assert host.run("end", target=target)
assert tmux("display-message", "-p", "-t", sibling, "#{pane_id}") == sibling
host.close()
print("Host protocol passed: typed wire, parallel preview, detached capture, fresh answers, reconnect, attach and guarded end")
