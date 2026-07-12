# Design: Fix launch window size (per-stack window frame restoration)

## Context

`HypeAppDelegate` (`Sources/Hype/HypeApp.swift:9-207`) saves one global window
frame via `AppLaunchState` (`Sources/Hype/AppLaunchState.swift`) and reapplies
it once at launch through `pendingWindowFrame` / `applyPendingWindowFrame(to:)`
(`HypeApp.swift:11-12, 172-178`). Defects, in order of severity:

1. **Unfiltered persistence.** Observers registered with `object: nil`
   (`HypeApp.swift:126-132`) make every window persist its frame via
   `persistState(for:)` (`HypeApp.swift:159-164`). The object-tool hover help
   panel alone (`ObjectsToolPanel.swift:60-62, 74-79` — ~340 pt wide, placed at
   the mouse) poisons the frame on every tool hover. `applicationWillTerminate`
   persists `NSApp.keyWindow ?? NSApp.mainWindow` (`HypeApp.swift:108-110`),
   which may be any auxiliary window.
2. **Write-before-read.** `windowDidBecomeMain` persists before applying the
   pending frame (`HypeApp.swift:191-192`).
3. **Discard-instead-of-clamp.** `visibleWindowFrame(using:)`
   (`AppLaunchState.swift:41-45`) requires only `intersects` (1 pt of overlap
   passes unclamped) and discards disconnected-display frames entirely.
4. **No per-stack identity.** A single global frame; last writer wins.

"Window size" = the NSWindow frame, app-local per `architecture.md:646`. The
document's `Stack.width/height` (canvas model, default 800×600,
`Sources/HypeCore/Models/Stack.swift:159-160`) is NOT touched; it is what makes
the fallback window "smaller" via `TargetCanvasFrameModifier`
(`MainContentView.swift:37-50, 929`).

## Goals / Non-Goals

Goals: stack window reopens at its last frame; auxiliary windows can never
poison it; restored frames are always fully on-screen; per-stack identity;
first-ever open unchanged (default size/placement); all storage logic pure and
unit-tested.

Non-Goals: mid-session frame restore when opening additional stacks (future
work); `setFrameAutosaveName`/scene-storage adoption; persisting geometry in the
`.hype` document; changing auxiliary windows' own size memory
(`scriptEditorWidth` etc., `PropertyInspector.swift:5435-5438` — untouched).

## Decisions

### D1. Storage: per-stack dictionary + legacy global fallback (AppLaunchState)

File: `Sources/Hype/AppLaunchState.swift` (modify).

New key in `Key` (after `lastOpenedFilePath`, line 9):
`windowFramesByPath = "lastWindowFrameByPath"` — `[String: [Double]]` mapping
canonical path → `[x, y, w, h, lastUsedEpochSeconds]`.

New constants: `maxStoredFrameEntries = 32`, `minimumRememberedDimension = 100`
(the existing `>100` rule, line 35).

New/changed API (all value-type, `Foundation`/`AppKit`-geometry only, no
NSWindow access — keeps the type headless-testable like today's
`AppLaunchStateTests`):

- `static func frameKey(forFileAt url: URL) -> String` —
  `url.standardizedFileURL.resolvingSymlinksInPath().path` so save and lookup
  agree for the same file.
- `var storedWindowFrame: NSRect?` — semantics unchanged, ADD `.isFinite`
  validation on all four components (lines 32-39).
- `func storedWindowFrame(forFileAt url: URL?) -> NSRect?` — per-path lookup
  with legacy fallback; `url == nil` → legacy only.
- `func restorableWindowFrame(forFileAt url: URL?, visibleScreenFrames: [NSRect]) -> NSRect?`
  — REPLACES `visibleWindowFrame(using:)` (lines 41-45; sole caller
  `HypeApp.swift:30-32`). Read-only — MUST NOT write defaults. Equals
  `storedWindowFrame(forFileAt:)` clamped via `clamped(_:toVisibleScreenFrames:)`.
- `static func clamped(_ frame: NSRect, toVisibleScreenFrames screens: [NSRect]) -> NSRect?`
  — pure clamping; nil only when screens is empty or frame invalid.
- `func save(windowFrame: NSRect, forFileAt url: URL?, now: Date = Date())` —
  REPLACES `save(windowFrame:)` (lines 47-52; sole caller `HypeApp.swift:160`).
  Always writes the four legacy scalar keys (global fallback / back-compat);
  when `url != nil` also upserts the per-path entry with `now` as lastUsed and
  prunes to `maxStoredFrameEntries` by evicting smallest lastUsed.

Clamping algorithm (screens are `NSScreen.visibleFrame` rects in global
bottom-left coordinates; negative origins possible — pure rect math):
1. Reject non-finite frames and frames with width/height ≤
   `minimumRememberedDimension` → nil.
2. If some screen fully contains the frame → return unchanged.
3. Pick the screen with the largest intersection area; if none intersects
   (disconnected display), pick `screens[0]` (delegate passes `NSScreen.screens`,
   index 0 = main).
4. `width = min(frame.width, screen.width)`, same for height.
5. `x = min(max(frame.minX, screen.minX), screen.maxX - width)`, same for y.
6. Return the resulting rect (always fully inside the chosen screen).

Validation shared by both read paths: exactly 5 elements for per-path (reject
malformed arrays), all values `.isFinite`, width/height >
`minimumRememberedDimension`.

### D2. Delegate: persist only document windows; per-URL pending frame

File: `Sources/Hype/HypeApp.swift` (modify `HypeAppDelegate` only; stays
`@MainActor`).

New stored property next to `pendingWindowFrame` (line 11):
`private var pendingWindowFrameURL: URL?` (stack the frame was computed for;
nil = untitled/global).

New identity helper above `fileURL(for:)` (line 166); rewrite `fileURL(for:)`
on it: `private func document(for window: NSWindow) -> NSDocument?` (the
windowControllers scan already production-proven in `fileURL(for:)` lines
166-170); `fileURL(for:) = document(for:)?.fileURL`.

`persistState(for:)` (lines 159-164) becomes: `guard let document =
document(for: window) else { return }` (the filter — THE fix), then
`launchState.save(windowFrame: window.frame, forFileAt: document.fileURL)`, and
if `document.fileURL != nil`, `launchState.save(fileURL: url)`.

`applicationDidFinishLaunching` (lines 30-32): set `pendingWindowFrameURL =
launchState.lastOpenedFileURL`, then `pendingWindowFrame =
launchState.restorableWindowFrame(forFileAt: pendingWindowFrameURL,
visibleScreenFrames: NSScreen.screens.map(\.visibleFrame))`.

`applyPendingWindowFrame(to:)` (lines 172-178): add identity guards that skip
WITHOUT consuming (`hasAppliedPendingFrame` stays false so a later becomeMain
can still apply): require `!hasAppliedPendingFrame`, a non-nil
`pendingWindowFrame`, a window, and `document(for: window) != nil`; then the
window's document-URL frameKey must equal the pending frameKey (nil == nil for
untitled) before `window.setFrame(frame, display: true)` and setting
`hasAppliedPendingFrame = true`.

`windowDidBecomeMain` (lines 180-193): reorder — keep
`window.acceptsMouseMovedEvents = true` first (unrelated tooltip fix), then
`applyPendingWindowFrame(to: window)`, then `persistState(for: window)`.
Removes the write-before-read hazard.

`openDocument(at:)` (lines 142-157): error branch (146-149) — before
`newDocument(nil)`, retarget the pending frame at the global fallback
(`pendingWindowFrameURL = nil`; recompute `restorableWindowFrame(forFileAt:
nil, …)`) so the untitled window restores the last document-window frame, not
the dead stack's. Success branch (151-156) — keep the apply attempt; replace
the `NSApp.keyWindow ?? NSApp.mainWindow` fallback with a single next-tick retry
(the existing next-tick pattern at 68-70). `windowDidBecomeMain` remains the
backstop; whichever fires first applies, the rest no-op via
`hasAppliedPendingFrame`.

`applicationWillTerminate` (108-110): prefer `NSApp.mainWindow ??
NSApp.keyWindow` (document windows are main; key may be a floating panel). The
`persistState` filter makes this safe regardless.

### D3. What deliberately does NOT change

Persist-on-every-move cadence (the per-path dict is ≤ 32 tiny entries; the added
read-modify-write per event is negligible; no `defaults.synchronize()`). No new
centering code. Auxiliary windows keep their own size memory
(`scriptEditorWidth`/`assetRepositoryWidth`).

## Dependency order

1. `AppLaunchState.swift` — storage, validation, clamping.
2. `Tests/HypeTests/AppLaunchStateTests.swift` — updated + new (Builder writes
   inline; one existing assertion changes).
3. `HypeApp.swift` delegate changes (consume the new API).
4. Docs: `architecture.md` persistence paragraph (~646) + `decisions.md`
   guardrail bullet; bump both `updated:` frontmatter.

## Risks / Trade-offs

- [SwiftUI may not have attached the window controller when the open-completion
  fires] → three independent, idempotent apply points (completion, next-tick
  retry, becomeMain) guarded by `hasAppliedPendingFrame`.
- [Per-event defaults writes now include a small dict upsert] → bounded at 32
  entries of 5 doubles; negligible; accepted.
- [Changing `visibleWindowFrame` semantics breaks an existing test] →
  intentional; the "hidden → nil" case (`AppLaunchStateTests.swift:40-43`)
  becomes "hidden → relocated on-screen" and is updated with the rename.
- [Stack file paths stored in UserDefaults] → same sensitivity class as the
  existing `lastOpenedFilePath` (architecture.md:646 sanctions local window
  geometry / prefs); LRU cap prevents unbounded growth.

## Testing notes

All new logic is pure and lives in `AppLaunchState` — test it headlessly in
`Tests/HypeTests/AppLaunchStateTests.swift` using the isolated-suite pattern
(`makeDefaults()`, lines 46-51) and content assertions (never nil-checks). No
test may create an NSWindow or depend on `NSScreen` (HypeTests must stay
headless-safe).

Required cases: per-path save/lookup round-trip; `frameKey` canonicalization
(symlink/`..` → same key); legacy-scalar fallback; untitled (nil URL) global
only; fully-visible unchanged; partially off-screen translated inside; oversized
capped; fully off-screen relocated to first screen; empty screen list → nil;
NaN/malformed → nil; LRU eviction at 33rd entry (assert exact surviving keys);
`restorableWindowFrame` performs no writes. Plus a seeded deterministic sweep
(~200 rects × 3 screen configs) asserting: result fully contained in one screen;
size preserved whenever the frame fits; idempotence (clamp∘clamp == clamp).

Delegate glue (observer filter, ordering, one-shot apply) is verified by
launching the real app (AGENTS.md deploy step): (1) resize/move → quit →
relaunch → same frame; (2) hover object tools + open script editor/About → quit
→ relaunch → stack frame unchanged; (3) quit with script editor key → relaunch →
unchanged; (4) fresh defaults → default size, remembered thereafter.

## Conditions for Builder

1. **Auxiliary windows must never write launch geometry.** The document-window
   guard in `persistState(for:)` is the fix; do not add any other call site
   that writes `lastWindowX/Y/Width/Height` or `lastWindowFrameByPath` without
   the same `document(for:)` guard.
2. **Never clobber the user's manual placement.** The saved frame is applied at
   most once per process (`hasAppliedPendingFrame`), only to the matching
   stack's document window, and never re-applied after the user could have
   moved/resized it. Skip-without-consume on identity mismatch is mandatory.
3. **Apply before persist.** In `windowDidBecomeMain`, the pending frame is
   applied before `persistState` runs. No path may overwrite stored geometry
   with a default frame before the restore has had its chance.
4. **A restored window must be fully on a visible screen.** Every frame passed
   to `setFrame` at launch comes from `clamped(_:toVisibleScreenFrames:)`; never
   call `setFrame` with an unclamped or unvalidated stored rect.
5. **Validate untrusted defaults.** UserDefaults content is untrusted input to
   `NSWindow.setFrame`: reject non-finite values, wrong arity, and dims ≤ 100
   before constructing an NSRect. Never crash on malformed entries.
6. **Per-stack identity.** Frames are keyed by `frameKey(forFileAt:)`
   (standardized + symlink-resolved path) on both save and lookup; two stacks
   must never share a per-path entry, and the launch apply must match the
   window's document URL against `pendingWindowFrameURL`.
7. **No writes on the read path.** `restorableWindowFrame` /
   `storedWindowFrame(forFileAt:)` / `clamped` must not mutate defaults.
8. **Bounded storage.** `lastWindowFrameByPath` never exceeds 32 entries; LRU
   eviction by `lastUsed`. No `defaults.synchronize()`.
9. **Main-actor correctness.** All delegate window handling stays `@MainActor`;
   do not add async gaps between reading `window.frame` and saving it.
10. **Scope discipline.** Do not touch `Stack.width/height`, the `.hype`
    document format, auxiliary windows' own size keys, or add
    `setFrameAutosaveName`/scene storage. No new UI. Do not stage or rewrite any
    `.hype` test fixtures (user documents).
11. **Tests must stay headless-safe.** Nothing in `AppLaunchStateTests` may
    create an NSWindow or depend on `NSScreen`; pass screen rects as plain
    values. Assert content, not existence.

### Added by Security (plan) — CONDITIONAL PASS

12. **Decode untrusted defaults with optional casts only.** Decode
    `lastWindowFrameByPath` using `as?` at every level — the top-level
    dictionary, each entry's array, each element — and treat ANY shape/type
    mismatch (a non-array, wrong element type, wrong arity) identically to "no
    saved frame for this path." No `as!` / forced `!` anywhere on this read
    path. (Security-code will grep the decode for forced casts.)
13. **Guard the clamp against degenerate screen rects.** Before choosing the
    best-intersection (or `screens[0]`) screen, drop any screen rect with
    non-positive width/height; if none remain, treat as "empty screens → nil."
14. **`.isFinite` covers all five elements** including the `lastUsed` timestamp
    (a NaN timestamp must not break LRU eviction / the 32-entry cap).
15. **System window-restoration:** confirmed there is NO
    `NSQuitAlwaysKeepsWindows` / window-restoration override in the tree and the
    delegate manually reopens the single `lastOpenedFileURL` — so multi-window-
    at-launch OS restoration does not apply to Hype. The residual multi-document
    persist race is accepted as self-healing, consistent with the Non-Goal "no
    mid-session frame restore for additional windows." Record this in the
    `decisions.md` guardrail bullet.
