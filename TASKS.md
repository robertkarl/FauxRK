# FauxRK handoff

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
- [x] Retire the two early icon concepts. FauxRK uses the user-selected four-tine fork artwork.

## FauxRK remote control

- [x] Record the Debra-only SSH workflow, helper installation, preset folders, and disconnect behavior in the design interview.
- [x] Run the live laptop → Debra RPC fixture. It captured a disposable process, steered literal Unicode text, answered a blocker, reconnected, spawned a real Luna Medium turn and cleaned up both sessions.
- [x] Implement and test shared host operations, SSH transport, and per-user helper bootstrap.
- [x] Integrate host picker, stale snapshot/draft handling, catch-up notifications, and local SSH terminal attachments.
- [x] Bundle the fork icon and the version-matched helper. Verify app signing and the running laptop window with a live connection to Debra.
- [x] Exercise simultaneous remote terminal attachments and stale-session refusal in real PTYs. Verify that a stalled iTerm Automation check leaves the attention poll responsive.
- [ ] On the laptop desktop, press **Open in New Window** twice for one captured Debra agent and confirm two iTerm2 windows. The signed GUI test reached the macOS Automation consent prompt and timed out before a client attached.
- [x] Pass the Opus release review and independent recheck, run the full suite, and prepare the verified laptop build for publication.

## Capture names

- [x] Verify recognizable names for isolated and shared sessions, literal tmux names, and existing captures.
- [x] Restore the reported session’s recognizable name, review the change, and deliver the laptop build.
