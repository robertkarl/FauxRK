# FauxRK

FauxRK (pronounced “fork”) is a native macOS sidebar for talking to agents that live in tmux panes. The idea is simple. Keep the durable session, the shell environment, and the tools you already use. Give the conversation a good interface.

The intended desk has FauxRK on the left and Netflix on the right. You can give an agent a task, answer the decision that’s holding it up, inspect what it produced in Preview or Firefox, and ask for a revision. iTerm2 can stay closed the whole time. When you want the raw session, **Open in New Window** attaches a fresh iTerm2 window to it.

## The first five minutes

1. Open FauxRK. Choose **This Mac** or **Debra**. **Other tmux panes** shows what’s running on the selected computer. **Sort by activity** puts current work near the top and holds the order while you browse.
2. Choose **Preview** to inspect an unfamiliar pane, or **Capture** to move a live pane into its own FauxRK-managed session. Existing work stays alive when FauxRK quits.
3. Choose **Spawn Agent** to start Astra Medium, Fable Medium, Opus, or Luna Medium in a project folder. You can leave the first prompt blank.
4. Expand a card to steer the conversation. Hold **F10** with the prompt focused to dictate locally. Release to insert the transcript, edit it, and send when ready.
5. Watch **Needs attention** for questions and turn completions. FauxRK quotes pending questions, offers recognized terminal choices, and lets you edit suggested replies. Opening a result marks it read. Answering a blocker in either FauxRK or tmux updates the same card.

## Build and run

Use macOS 14 or later with the Xcode command-line tools and a local tmux installation. Agent presets use the signed-in Claude Code and Codex CLIs from your interactive zsh environment. Preset names reflect the original workstation’s model access. Each machine needs access to the selected model. The Codex presets use a CLI with local app-server daemon support.

```sh
make
make test
make install
open ~/Applications/FauxRK.app
```

FauxRK uses Objective-C and programmatic AppKit. The build creates a self-contained app bundle for the UI. Agent runtimes, tmux, and inference tools run on the host. The build uses an installed Apple Development identity when available and falls back to ad hoc signing. Set `SIGN_ID` to choose a particular identity. Using the same development identity across builds lets macOS remember the app’s permissions.

To open a launch draft for a specific project when starting FauxRK on This Mac, run <code>open ~/Applications/FauxRK.app --args -RKProject "$PWD"</code>.

## Drive Debra from the laptop

Choose **Debra** in the sidebar. On a LAN, allow FauxRK under **System Settings → Privacy &amp; Security → Local Network** when macOS asks. FauxRK uses your existing OpenSSH configuration for `debra` and requires a trusted host key and noninteractive login. To use a different trusted SSH destination for Debra, set it before launching the app.

```sh
defaults write net.robertkarl.RK FauxRKDebraDestination your-ssh-alias
```

Debra needs a compatible Mac, tmux, and the agent CLIs you want to run. FauxRK installs its matching helper under your account on Debra and runs it over the SSH connection. Spawn uses the regina, homelab, and unbiasedbob-private folders in your home directory on Debra. Dictation uses the laptop microphone. **Open in New Window** opens iTerm2 on the laptop and attaches over SSH.

If the connection drops, your tmux sessions continue running. The sidebar keeps your last view and drafts, shows when it last saw Debra, and retries automatically. Check the agent after an unconfirmed send before submitting again. Switching computers clears the current drafts. FauxRK remembers the selected computer when you quit. Run one dashboard at a time. Two controllers monitoring the same computer can overwrite each other’s read receipts.

## Helpers and voice

The hosted helper uses your **claudesonnet** alias in a fresh tmux window on the same server. Helper windows are temporary and visible while they run. The helper reads the last screenful of managed panes and any unmanaged pane you explicitly preview. Choose **FauxRK → Helper Settings** to use Ollama on the selected computer.

Dictation uses `whisper-cli` and a local whisper.cpp model. Existing models in the supported cache locations work automatically. You can also set `RK_WHISPER_MODEL` to a model file. The optional `scripts/setup-voice.sh` installs the CLI and downloads a model. macOS requests microphone access on first use. FauxRK requests notification access when you first manage an agent.

The five-second blocker target includes prompts already waiting when you reopen FauxRK. Terminal layouts and agent versions vary. Unrecognized stationary output can appear as **May need input** while a helper interprets it.

## Design record

The original mockups and the choices behind the sidebar are in the repository. The short task list records what has been verified and what still needs hands-on testing. [Project handoff](TASKS.md). [Design interview](Docs/Design/Decisions.md) · [Compact dashboard](Docs/Design/Neon%20Agent%20Control%20Dashboard%281%29.png) · [Expanded dashboard](Docs/Design/Expanded%20Agent%20Control%20Dashboard.png) · [Acceptance criteria](SPEC.md)
