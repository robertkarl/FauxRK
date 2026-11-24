## Code Review: UTF-8 tmux client output

**Verdict: PASS** for commit `752181a`.

### Findings

No findings.

In an isolated tmux 3.5a session, a client with `LC_ALL=C` returned `10:unicode-_` for the name `unicode-Ω`. The field contained nine bytes despite its declared length of ten. With `-u`, the same query returned `10:unicode-Ω`, preserving all ten UTF-8 bytes. The shared RKCore launcher applies the flag to both inventory and capture queries.

`Tests/core.sh` passed, including capture of a Unicode session under the C locale.
