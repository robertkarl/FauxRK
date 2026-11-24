# RK first release
RK is a local macOS sidebar for talking to terminal agents. Build its native UI in Objective-C and AppKit without storyboards. The core acceptance scenario starts with iTerm2 quit and a local tmux server running.

- [ ] First launch lists unmanaged panes without importing them. Sort by activity on demand and hold row order during polling.
- [ ] Capture deliberately transfers the live pane to a marked, single-pane session. Restore managed cards after relaunch. Spawn creates the same layout with a preset, project directory, and optional prompt.
- [ ] Offer Astra Medium, Fable Medium, Opus, and Luna Medium and shortcuts for regina, homelab, and unbiasedbob-private.
- [ ] Steer from a card. Preserve ordering of pending messages. Interrupt sends one C-c. End requires confirmation, sends two interrupts, then closes the managed session. Open in New Window opens a fresh iTerm2 window every time.
- [ ] Support a hosted or local helper, on-demand preview for unmanaged panes, and automatic summaries and blocker detection for managed panes. Surface uncertainty. Refresh before sending an answer.
- [ ] Target five seconds from a visible blocker to an attention row, including startup. Keep one item per agent. Keep blockers until resolved, mark completed turns read on opening, and suppress macOS banners for the pane the user is interacting with.
- [ ] Request notification permission on first use with an agent. Opening a notification reveals the associated card. Use a short summary for completed turns. Show real terminal choices as actions, and helper suggestions as editable drafts.
- [ ] Hold F10 with an RK prompt focused to record locally and transcribe with Whisper. Release inserts an editable draft. No global shortcut in this release.
- [ ] Keep the narrow sidebar resizable, with optional Keep on Top. Defer Aside. The terminal is an optional escape hatch.
