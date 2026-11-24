## Code Review: Initial RK release

**Verdict: PASS**

Reviewed the release against the empty main baseline. Review commit 7c7c9ed and project commit e9ecde5 have the same Git tree. Both `make` and `make test` passed in the review checkout.

### Findings

No open blockers or warnings.

#### NOTE: Foreground notification behavior

- **File:** Sources/RKAlerts.m:48
- **Observation:** RK suppresses all banners while its own window is active. In a terminal it checks focus per pane. Tests/alerts.m:113 explicitly covers app-wide foreground suppression.

### Corrections verified

- Sources/RKSidebar.m:225 now closes a preview when the underlying tmux target changes. The Capture action also checks the original target.
- Sources/RKApp.m:200 now leaves the separate steering draft intact after a successful reply.
- Sources/RKAgentCardView.m:107, Sources/RKAgentCardView.m:205 and Sources/RKSpawnView.m:31 copy editor text before a worker receives it. An AppKit probe confirmed the need for these copies: the retained original string changed after its text storage was edited.
- Sources/RKMonitor.m:205 implements the guarded steering selector and checks the current screen before forwarding the message.
