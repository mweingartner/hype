## 1. AppLaunchState storage, validation, clamping

- [x] 1.1 Add `Key.windowFramesByPath`, `maxStoredFrameEntries` (32),
      `minimumRememberedDimension` (100), and
      `static func frameKey(forFileAt:) -> String` to
      `Sources/Hype/AppLaunchState.swift`.
- [x] 1.2 Add `.isFinite` validation to `storedWindowFrame` (lines 32-39) and
      implement `storedWindowFrame(forFileAt:)` with per-path lookup +
      legacy-scalar fallback, sharing one validator (finite, dims > 100,
      exact 5-element arity for per-path entries).
- [x] 1.3 Implement pure `static func clamped(_:toVisibleScreenFrames:) -> NSRect?`
      per design D1 (contained → unchanged; largest-intersection screen else
      screens[0]; size capped; origin clamped inside).
- [x] 1.4 Replace `visibleWindowFrame(using:)` with
      `restorableWindowFrame(forFileAt:visibleScreenFrames:)` (read-only), and
      `save(windowFrame:)` with `save(windowFrame:forFileAt:now:)` (legacy
      scalars always; per-path upsert + LRU prune when url != nil).

## 2. Unit tests (Builder writes inline, same pass)

- [x] 2.1 Update `Tests/HypeTests/AppLaunchStateTests.swift` for the renamed
      API; change the `hidden` assertion (lines 40-43): fully off-screen frame
      now relocates fully inside the provided screen (assert the exact clamped
      rect).
- [x] 2.2 Add tests: per-path round-trip; frameKey canonicalization; legacy
      fallback; nil-URL global behavior; partial off-screen translation;
      oversized capping; disconnected-display relocation; empty screens → nil;
      NaN/malformed → nil; LRU eviction at 33 entries (assert surviving keys);
      read path performs no writes.
- [x] 2.3 Add the seeded deterministic clamp sweep (~200 rects × 3 screen
      configs) asserting: containment in some screen, size preserved when it
      fits, and idempotence (clamp(clamp(x)) == clamp(x)).
- [x] 2.4 Run `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --filter AppLaunchStateTests`
      — real, non-zero test count required.

## 3. HypeAppDelegate wiring

- [x] 3.1 Add `pendingWindowFrameURL`; add `document(for:) -> NSDocument?` and
      rewrite `fileURL(for:)` on top of it (`HypeApp.swift:166-170`).
- [x] 3.2 Guard `persistState(for:)` (lines 159-164) on
      `document(for:) != nil`; save via `save(windowFrame:forFileAt:)`.
- [x] 3.3 Compute the pending frame per-URL in `applicationDidFinishLaunching`
      (lines 30-32) via `restorableWindowFrame(forFileAt:visibleScreenFrames:)`.
- [x] 3.4 Harden `applyPendingWindowFrame(to:)` (lines 172-178): document
      guard + frameKey identity match, skip-without-consume.
- [x] 3.5 Reorder `windowDidBecomeMain` (lines 180-193): apply before persist
      (keep `acceptsMouseMovedEvents` first).
- [x] 3.6 `openDocument(at:)`: retarget pending frame to global fallback in the
      error branch (lines 146-149); replace the key/main fallback in the
      success branch (lines 151-156) with the single next-tick retry.
- [x] 3.7 `applicationWillTerminate` (lines 108-110): use
      `NSApp.mainWindow ?? NSApp.keyWindow`.

## 4. Full suite + docs

- [x] 4.1 Run the gated suite:
      `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --no-parallel --filter HypeCoreTests --filter HypeCLITests`
      plus the AppLaunchState filter from 2.4; keep the interpreter fuzz suite
      green.
- [x] 4.2 Update `architecture.md` (persistence/window-geometry paragraph near
      line 646) and add the `decisions.md` guardrail bullet ("only stack
      document windows persist launch geometry"); bump both `updated:`
      frontmatter.

## 5. Deploy-readiness verification (real target)

- [ ] 5.1 Build and install per AGENTS.md
      (`./script/build_and_run.sh --deploy`, then open `/Applications/Hype.app`).
- [ ] 5.2 Manual matrix: (a) resize+move stack window → quit → relaunch →
      identical frame; (b) hover object tools, open script editor + About →
      quit → relaunch → stack frame unchanged; (c) quit with script editor as
      key window → relaunch → stack frame unchanged; (d) fresh defaults →
      default size at first launch, remembered thereafter.
