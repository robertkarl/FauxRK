# RK handoff

## Verified

- [x] Native Objective-C sidebar builds. Both original screenshots and the interview decisions are in Docs/Design.
- [x] Detached spawn/capture, stable inventory, safe End, two distinct iTerm2 windows, answering a real Claude prompt, and mid-turn Codex steering.
- [x] Visible Sonnet helper windows on the main server, local Ollama summaries, and local Whisper transcription into an editable draft.
- [x] Tested startup and completion parsing against real CLI screens. Detached end-to-end regression covers capture → answer → reopen → steer.

## Release work in progress

- [x] Verify both medium Codex presets can execute a real shell tool. The explicit shared-daemon launch passed for Astra and Luna (6879a0b).
- [ ] Finish live Claude menu coverage, including choices with multiline descriptions and custom status lines.
- [ ] Finish Fable code review, resolve actionable findings, and rerun make test and make.
- [ ] Install ~/Applications/RK.app, open a spawn draft in this repository, push main to robertkarl/RK, and verify the remote commit.

## First hands-on session

- [ ] With the Mac unlocked, check the system microphone and notification permission prompts, F10 with a physical microphone, and notification delivery while switching between real agent windows.

Continue from git status and this list. Scratch builds, review logs, and smoke-test outputs belong under the ignored build/ directory. The Mac was locked during UI verification; AppKit renders and responder tests ran successfully.
