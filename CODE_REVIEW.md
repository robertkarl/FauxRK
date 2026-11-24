## Code Review: Preserve captured tmux names

**Verdict: PASS** for commit `4fe99c1`.

### Findings

No open findings. I reran the original regression in an isolated tmux 3.5a server. Inventory listed the shared pane under `Alpha` first, while a pane-only lookup still returned `Zebra`. Capture preserved `Alpha` as both the session name and the card label.

`Tests/core.sh` passed. It also exercises explicit selection of a linked session, rejection of an unrelated session, fallback names when siblings remain, literal punctuation and backslashes, and a user rename after capture. I traced the selected session ID from the discovery row through the host request to the move. The sidebar and individual notifications use the captured label.
