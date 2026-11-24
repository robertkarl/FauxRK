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

## FauxRK on the laptop

- [x] Select exactly one target, This Mac or Debra. Relaunch restores that selection. A deliberate switch clears the previous target's cards, previews, and drafts.
- [x] Selecting Debra establishes SSH, installs the matching per-user helper when needed, and starts it for the connection. Closing the UI leaves Debra's tmux agents running.
- [x] Remote snapshots, capture, preview, spawn, interrupts, approvals, steering, and confirmed End address Debra. Remote Spawn resolves only the three project shortcuts on Debra. Free text reaches the agent unchanged.
- [ ] Each Open in New Window opens local iTerm2, SSHs to Debra, and attaches to the guarded managed session.
- [x] A lost connection retains the last snapshot, last-seen time, and drafts. Sending is disabled until reconnect, and an interrupted submission is reported as unconfirmed and never automatically resent.
- [x] On reconnect, outstanding handoffs produce at most one catch-up notification. Live handoffs afterward notify individually.
- [x] The native bundle displays the FauxRK name and the selected four-tine fork icon while retaining local RK preferences and tmux ownership markers.

## Capture names

- [ ] Capture uses the original tmux session name as the card title, with the window name in the details. Attention rows and individual notifications use that session name after capture and reconnect.
- [ ] The dedicated tmux session reuses the source session name when available. If another window still needs that name, the new session includes the original session and window names with a readable disambiguator if necessary.
- [ ] Capture preserves the live pane, its process and the window name. Spawning and existing captures without recorded names keep their current behavior.
