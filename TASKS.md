# RK handoff

## Verified

- [x] Native Objective-C sidebar builds. Both original screenshots and the interview decisions are in Docs/Design.
- [x] Detached spawn/capture, stable inventory, safe End, two distinct iTerm2 windows, answering a real Claude prompt, and mid-turn Codex steering.
- [x] Visible Sonnet helper windows on the main server, local Ollama summaries, and local Whisper transcription into an editable draft.
- [x] Tested startup and completion parsing against real CLI screens. Detached end-to-end regression covers capture → answer → reopen → steer.

- [x] Astra Medium and Luna Medium each executed a shell tool through the shared local Codex daemon (6879a0b).
- [x] Real Fable menu answers and completed turns are recognized. A steer sent during a running shell tool changed the next action before the turn finished.
- [x] Fable reviewed the plan and code. The release code review passed; findings and verified corrections are in CODE_REVIEW.md.
- [x] Build, install, and open the RK development project as a spawn draft on the local Mac.

## First hands-on session

- [ ] With the Mac unlocked, check the system microphone and notification permission prompts, F10 with a physical microphone, and notification delivery while switching between real agent windows.

Continue from git status and this list. Scratch builds, review logs, and smoke-test outputs belong under the ignored build/ directory. The Mac was locked during UI verification. AppKit renders and responder tests passed. The test run also left a trust entry for a disposable Claude workspace in local Claude settings.

## Dashboard visual update

- [x] Match compact and expanded cards, the tmux inventory, and attention items to the original mockups. Check narrow layout, responder stability, and direct blocker choices.
- [x] Review both icon concepts on the laptop. Icon selection is deferred.

## FauxRK remote control

- [x] Record the Debra-only SSH workflow, helper installation, preset folders, and disconnect behavior in the design interview.
- [ ] Verify the full remote workflow on the laptop once implemented.
