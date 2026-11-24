# RK

RK is a native macOS sidebar for talking to agents that live in tmux panes. The idea is simple. Keep the durable session, the shell environment, and the tools you already use. Give the conversation a good interface.

The intended desk has RK on the left and Netflix on the right. You can give an agent a task, answer the decision that’s holding it up, inspect what it produced in Preview or Firefox, and ask for a revision. iTerm2 can stay closed the whole time. When you want the raw session, **Open in New Window** attaches a fresh iTerm2 window to it.

## The first five minutes

1. Open RK. **Other tmux panes** shows what’s running locally. **Sort by activity** puts current work near the top and holds the order while you browse.
2. Choose **Preview** to inspect an unfamiliar pane, or **Capture** to move a live pane into its own RK-managed session. Existing work stays alive when RK quits.
3. Choose **Spawn Agent** to start Astra Medium, Fable Medium, Opus, or Luna Medium in a project folder. You can leave the first prompt blank.
4. Expand a card to steer the conversation. Hold **F10** with the prompt focused to dictate locally. Release to insert the transcript, edit it, and send when ready.
5. Watch **Needs attention** for questions and turn completions. RK quotes pending questions, offers recognized terminal choices, and lets you edit suggested replies. Opening a result marks it read. Answering a blocker in either RK or tmux updates the same card.

## Build and run

Use macOS 14 or later with the Xcode command-line tools and a local tmux installation. Agent presets use the signed-in Claude Code and Codex CLIs from your interactive zsh environment. Preset names reflect the original workstation’s model access. Each machine needs access to the selected model.

```sh
make
make test
make install
open ~/Applications/RK.app
```

RK uses Objective-C and programmatic AppKit. The build creates a self-contained app bundle for the UI. Agent runtimes, tmux, and inference tools run on the host. For a stable local signing identity across rebuilds, pass your local identity as the Make variable `SIGN_ID` when building.

## Helpers and voice

The hosted helper uses your **claudesonnet** alias in a fresh tmux window on the same server. Helper windows are temporary and visible while they run. The helper reads the last screenful of managed panes and any unmanaged pane you explicitly preview. Choose **RK → Helper Settings** to use a local Ollama model instead.

Dictation uses `whisper-cli` and a local whisper.cpp model. Existing models in the supported cache locations work automatically. You can also set `RK_WHISPER_MODEL` to a model file. The optional `scripts/setup-voice.sh` installs the CLI and downloads a model. macOS requests microphone access on first use. RK requests notification access when you first manage an agent.

The five-second blocker target includes prompts already waiting when you reopen RK. Terminal layouts and agent versions vary. Unrecognized stationary output can appear as **May need input** while a helper interprets it.

## Design record

The original mockups and the choices behind the sidebar are in the repository. [Design interview](Docs/Design/Decisions.md) · [Compact dashboard](Docs/Design/Neon%20Agent%20Control%20Dashboard%281%29.png) · [Expanded dashboard](Docs/Design/Expanded%20Agent%20Control%20Dashboard.png) · [Acceptance criteria](SPEC.md)
