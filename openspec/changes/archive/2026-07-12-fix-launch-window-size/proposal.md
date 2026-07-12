# Fix launch window size: restore the stack window's last saved frame

## Why

At launch Hype reopens the correct last stack but at the wrong geometry — a
smaller window, positioned off-center — instead of the size and position it had
when last used. Root cause: the app delegate's frame-persistence observers are
registered for every `NSWindow` in the process (`object: nil`,
`Sources/Hype/HypeApp.swift:126-132`), so auxiliary windows — the object-tool
hover help panel (`ObjectsToolPanel.swift:60-62`, sized ~340 pt and positioned
at the mouse cursor), script editor, asset repository, About, console, Theme
Designer, import helper windows, and the Settings window — overwrite the single
global saved frame (`AppLaunchState.swift:47-52`); `applicationWillTerminate`
likewise persists whatever window happens to be key (`HypeApp.swift:108-110`).
The next launch applies that poisoned frame (or, when it fails the validity /
visibility guard, falls through to the default ~800×600 cascade window).

## What Changes

- Persist window geometry **only for stack document windows**: `persistState`
  gains a document-window identity guard (NSDocumentController
  window-controller scan, generalizing the existing `fileURL(for:)` helper at
  `HypeApp.swift:166-170`). Auxiliary windows never write launch geometry.
- Key saved frames **per stack file** in `AppLaunchState` (canonicalized path →
  frame + last-used timestamp, LRU-capped), keeping the legacy global keys as
  the untitled-window fallback and backward-compat read.
- Launch restore looks up the frame **by the URL being reopened** and **clamps
  it to the visible screens** (preserve size when it fits, cap to screen when it
  doesn't, relocate fully off-screen frames) instead of discarding it.
- Fix the persist-before-apply ordering in `windowDidBecomeMain`
  (`HypeApp.swift:191-192`): apply the saved frame first, then persist.
- First-ever open (no saved frame) keeps today's default size and system
  placement — no new centering code.
- Non-goals: no change to `Stack.width/height` (document canvas model), no
  mid-session frame restore for additional windows, no `setFrameAutosaveName`
  adoption, no document-format change.

## Capabilities

### New Capabilities
- `window-restoration` — persistence and launch-time restoration of stack
  window geometry.

### Modified Capabilities
- None (no existing spec covers window geometry; behavior previously implicit).

## Impact

- `Sources/Hype/AppLaunchState.swift` — per-stack frame storage, validation,
  clamping (pure logic, unit-testable).
- `Sources/Hype/HypeApp.swift` — `HypeAppDelegate` persistence filter, apply
  ordering, pending-frame identity.
- `Tests/HypeTests/AppLaunchStateTests.swift` — extended; one existing
  assertion changes (off-screen frame now relocates instead of returning nil).
- `architecture.md` + `decisions.md` — document the guardrail: only document
  windows persist launch geometry.
- No persisted `.hype` document shape change — no `HypeDocument` version bump.

## Design phases: N/A (rationale)

This change has no UI/UX design component: it introduces no new surface,
element, state, or interaction pattern, and makes no visual-design decision. It
restores already-designed behavior — the window reopens exactly where the user
left it, using the user's own saved geometry. Correctness of the restored
geometry is verified in Security/Test, not Design. Per AGENTS.md ("Only the
three Design stages may be marked N/A … with a written rationale"), Design
Mock, Design Review, and Design Sign-off are marked N/A with this rationale.
