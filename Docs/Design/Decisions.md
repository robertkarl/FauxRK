# RK design interview

RK is a first-class place to talk to agents. The intended desk has RK at the left and Netflix at the right. Agents can open results in Preview, Firefox, or another appropriate app. Opening a terminal is an explicit escape hatch. The two original PNGs in this directory show the compact dashboard and expanded agent card. The decisions below refine those references.

## Ownership and discovery

- Manage the local tmux server. RK works with iTerm2 quit and no terminal clients attached.
- First launch starts with zero cards unless a previous RK installation already marked sessions. Detecting an agent never captures it.
- Rank other panes by actual client focus, apparent agent activity, and recent activity. Hold their order while the user browses. Append new arrivals. A manual sort brings active work to the top.
- Preview summarizes one uncaptured pane on demand. Capture moves its live pane to a dedicated session, preserving the running process and scrollback. A client disconnect during capture is acceptable.
- A captured or spawned agent has one session, one window, and one pane. Treat a login window as one invocation. Multiple successive agents in the same login window were outside the design discussion.
- Use recognizable session names and durable tmux markers. Reopening RK restores the cards without another capture. Quitting RK leaves the sessions running.
- Name a card automatically from tmux, the folder, or a helper summary. No naming dialog.

## Starting and talking to agents

- Spawn deliberately captures the new run. Offer Astra Medium, Fable Medium, Opus, and Luna Medium, in that order. Local/pi and Astra High came up as personal choices for future presets.
- Offer ~/Code/regina/, ~/homelab/, ~/Code/unbiasedbob-private/, and another folder. An initial prompt is optional.
- Hold F10 to dictate with local Whisper when an RK prompt editor has focus. Release produces an editable draft. With only a card selected, F10 does nothing. A global shortcut was deferred.
- For a busy agent, steer at the next supported opportunity in the current turn. Preserve the order of multiple pending messages. Concatenating them with a blank line is acceptable.
- Interrupt sends one Ctrl-C. Confirm End session, send two Ctrl-Cs while the agent is alive, then close the managed session. The provider's on-disk conversation history is the recovery path.
- Every click on Open in New Window opens another iTerm2 window attached to the same session.
- Defer Aside and its fork semantics.

## Helpers and attention

- The app can run cheap helpers using hosted Sonnet or Luna, or local inference. Design for short time to first token (roughly one second). Hosted checks may read captured screenfuls automatically. Uncaptured panes are summarized on explicit Preview.
- Blocker detection is a core feature. Aim to surface visible requests within five seconds, including ones already waiting on reconnect. Favor surfacing uncertain requests over overlooking a blocked agent.
- Offer actual terminal choices as clickable actions and verify the prompt before sending. Helper-written answers to open questions are editable suggestions.
- Show one attention item per agent. A blocker stays visible after being read and clears when resolved, including from tmux directly. A completed turn gets a one-line summary and clears on opening. Remember read state across app restarts.
- Ask for macOS notification permission. Include the agent title and short question or result. Opening the notification opens the card. Suppress notifications for the pane the user is interacting with, including in iTerm2. Activity in another agent’s terminal does not suppress the first agent’s notification.
- Whether to notify after leaving a previously focused, still-blocked pane was left open.

## Window behavior

Start with a narrow resizable sidebar, ordinary window level by default, and optional Keep on Top. Revisit the design after living in the app. The five-second latency and agent behavior are product targets that need validation with real sessions.
