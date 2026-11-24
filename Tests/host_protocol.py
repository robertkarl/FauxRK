"""Exercise the real JSONL helper against a private tmux server and a terminal fixture."""

import json
import os
import plistlib
import shutil
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
    def __init__(self, executable=binary):
        self.proc = subprocess.Popen([executable], stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0)

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
# Model a previous checksum-named installation's on-disk receipt ledger.
prefs = Path(os.environ["CFFIXED_USER_HOME"]) / "Library/Preferences"
prefs.mkdir(parents=True, exist_ok=True)
legacy = {"legacy-agent": {"id": "prior-event", "signature": "prior-screen", "read": True}}
(prefs / ("FauxRKHost-" + "a" * 64 + ".plist")).write_bytes(plistlib.dumps({"RKLastHandoffsV1": legacy}))
host = Host()
host.write(b"[]\n")
assert host.receive()["id"] is None
host.write(b'{"id":12,"args":{},"op":"snapshot"}\n')
assert "error" in host.receive()
assert host.run("system", expect_error=True)
assert host.run("end", expect_error=True, target=pane_id)
assert host.run("snapshot", expect_error=True, provider="unknown")
assert host.run("snapshot", expect_error=True, unexpected=True)
assert "panes" in host.run("snapshot", provider="sonnet", model="")
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
stored = plistlib.loads(subprocess.check_output(["defaults", "export", os.environ["RK_HOST_FIXTURE_SUITE"], "-"]))
assert stored["RKLastHandoffsV1"]["legacy-agent"] == legacy["legacy-agent"]
raw = source["target"]

# A blocked preview never holds up snapshot or control traffic.
previews = {host.send("preview", target=raw) for _ in range(3)}
deadline = time.monotonic() + 5
while not (work / "preview-started").exists() and time.monotonic() < deadline:
    time.sleep(.03)
assert (work / "preview-started").is_file()
assert "busy" in host.run("preview", expect_error=True, target=raw)
host.run("snapshot", provider="sonnet", model="qwen3:4b", focusToken="")
(work / "release-preview").touch()
while previews:
    reply = host.receive()
    assert reply["value"] == "The isolated fixture wants an answer.", reply
    previews.remove(reply["id"])

assert host.run("capture", target=raw, sourceSessionID="$987654", expect_error=True)
assert host.run("capture", target=raw, sourceSessionID=source["sessionID"]) is True
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
upgraded = work / "FauxRKHost-upgraded-fixture"
shutil.copy2(binary, upgraded)
host = Host(upgraded)
restored = host.run("snapshot")
assert any(p["rkID"] == owned["rkID"] for p in restored["panes"])
assert not restored["attention"], "A previously read result resurfaced on reconnect"
assert host.run("end", target=target)
assert tmux("display-message", "-p", "-t", sibling, "#{pane_id}") == sibling
# Foundation expands the remote user's tilde on the host. A fresh test home
# and fake provider CLIs exercise all supported paths without touching real projects.
for directory, preset in (("~/Code/regina/", "Astra Medium"), ("~/homelab/", "Fable Medium"), ("~/Code/unbiasedbob-private/", "Luna Medium")):
    project = Path(os.environ["CFFIXED_USER_HOME"]) / directory[2:]
    prompt = "show me the pdf\nKeep this literal: $(echo q) 💬"
    new_id = host.run("spawn", preset=preset, directory=directory, prompt=prompt)
    deadline = time.monotonic() + 5
    invocation = project / "invocation.json"
    while not invocation.exists() and time.monotonic() < deadline:
        time.sleep(.03)
    actual = json.loads(invocation.read_text())
    assert Path(actual["cwd"]).resolve() == project.resolve() and actual["args"][-1] == prompt, actual
    created = next(p for p in host.run("snapshot")["panes"] if p["id"] == new_id)
    assert created["managed"] and created["preset"] == preset, created
    assert host.run("interrupt", target=created["target"])
    deadline = time.monotonic() + 2
    while not (project / "interrupted").exists() and time.monotonic() < deadline:
        time.sleep(.03)
    assert (project / "interrupted").is_file()
    assert host.run("end", target=created["target"])
host.close()

# On EOF, both a manually requested preview and an automated pane assessment
# must reach their cleanup handlers before the SSH process exits.
pane_id = tmux("new-session", "-dP", "-F", "#{pane_id}", "-s", "eof-fixture", sys.executable, "-u", str(script), str(work))
host = Host(upgraded)
source = next(p for p in host.run("snapshot")["panes"] if p["id"] == pane_id)
assert host.run("capture", target=source["target"])
owned = next(p for p in host.run("snapshot", provider="sonnet")["panes"] if p["id"] == pane_id)
(work / "release-preview").unlink()
jobs = work / "preview-dirs"
previous = len(jobs.read_text().splitlines())
time.sleep(.75)
host.run("snapshot")
host.send("preview", target=owned["target"])
deadline = time.monotonic() + 5
while len(jobs.read_text().splitlines()) < previous + 2 and time.monotonic() < deadline:
    time.sleep(.03)
dirs = [Path(p) for p in jobs.read_text().splitlines()[previous:]]
assert len(dirs) == 2 and all((p / "in").is_file() for p in dirs), dirs
host.proc.stdin.close()
try:
    host.proc.wait(timeout=.2)
    raise AssertionError("EOF abandoned active inference before cleanup")
except subprocess.TimeoutExpired:
    pass
(work / "release-preview").touch()
host.close()
assert all(not path.exists() for path in dirs), dirs
sessions = tmux("list-sessions", "-F", "#{session_name}").splitlines()
assert not any(name.startswith("rk-helpers-") for name in sessions), sessions
assert tmux("display-message", "-p", "-t", pane_id, "#{pane_id}") == pane_id
print("Host protocol passed: typed wire, parallel preview, detached capture, fresh answers, reconnect, attach, guarded end and EOF cleanup")
