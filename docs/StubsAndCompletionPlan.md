# Stubs & Completion Plan

> Snapshot: 2026-05-23 · HEAD `99bd9ce` · 2124 tests / 236 suites green
> Method: four parallel codebase audits — (1) literal stub-marker census across
> ~110k LOC, (2) HypeTalk language-surface completeness, (3) design-doc deferred-
> feature census vs. shipped reality, (4) provider/integration completeness.
>
> **Headline:** Hype is mature. There is **no dead feature, no stub leaking into a
> production path, and no doc-vs-code drift.** The gaps that remain cluster into
> three buckets: (A) HyperTalk legacy-command completeness, (B) Apple-framework
> interaction depth, and (C) a handful of large architectural-runway bets that are
> intentionally parked. The single biggest lever is already proven in the
> codebase — the `SystemProvider` protocol that the audio workstream just fully
> populated. Most remaining "interpreter stubs" are resolved by the same
> dependency-injection move.

---

## 1. What is NOT a gap (so we don't chase ghosts)

The audits surfaced a lot of `fatalError` / `Stub*` / no-op markers that are
**correct as-is**. Recording them here so a future review doesn't re-flag them:

- **18× `required init?(coder:) { fatalError("not used") }`** on programmatically
  created `NSView` / `SKNode` subclasses. Standard AppKit/SpriteKit idiom — these
  views are never deserialized from a XIB.
- **8 `Stub*` provider types** (`StubDialogProvider`, `StubDrawingProvider`,
  `StubSystemProvider`, `StubAIScriptingProvider`, `StubSpeechOutputProvider`,
  `StubSpeechListenerProvider`, `StubMeshyScriptingProvider`,
  `StubAppleMusicProvider`). Every one is a default-parameter / test seam that
  production overrides. Verified: no stub is the sole path a real user hits.
- **The audio/system-provider workstream is COMPLETE**, not in-progress.
  `AppKitSystemProvider` fully implements `beep` / `playSound` / `playNotes` /
  tone synthesis / Apple Music and is wired into all three UI entry points
  (`AIChatPanel`, `NetworkPanelView`, `MessageBoxView`). It just needs to be
  committed (it is currently uncommitted on disk).
- **Meshy webhook is decoder-only by design.** No always-on listener — the
  `listen for http` HypeTalk primitive is the documented manual path. Not a gap.
- **Phase-3 Apple frameworks** (ContactsUI, EventKit events, OAuth,
  UserNotifications, AVKit PiP, CoreLocation user-location) are documented
  intentional deferrals. Listed in §5 as demand-driven, not as bugs.
- **`#warning` directives: none.**

---

## 2. The real gaps, by cluster

### Cluster A — HyperTalk legacy-command completeness (highest user-facing impact)

These commands/functions **parse successfully** but do nothing or return empty.
A user porting a HyperCard stack, or following the HyperTalk guide, hits silence.
The worst sub-class is "silent no-op" — parses, runs, zero feedback, hard to debug.

| # | Surface | Location | State | What the user sees |
|---|---------|----------|-------|--------------------|
| A1 | `find "text"` + `the foundText` / `foundChunk` / `foundField` / `foundLine` | Interpreter.swift:1458; getters 3194–3199 | PARTIAL — stores term in `it`, never searches | `find` highlights nothing; `the foundText` always `""` |
| A2 | `select <chunk> of <field>` + `the selectedText` / `selectedChunk` / `selectedField` / `selectedLine` / `selectedLoc` / `selectedButton` | Interpreter.swift:1463; getters 3194–3199 | NO-OP | No field selection; `the selectedText` always `""` |
| A3 | `sort cards by <expr>` | Interpreter.swift:1466 | PARTIAL — evaluates expr, never reorders | Card order unchanged |
| A4 | `push card` / `pop card` + `recent cards` | Interpreter.swift:2600 catch-all | SILENT NO-OP | Card-history navigation does nothing |
| A5 | `lock screen` / `unlock screen` | Interpreter.swift:1487 | NO-OP | No redraw batching; flicker on bulk edits |
| A6 | `do <expr>` (eval a string as HypeTalk) | Interpreter.swift:1361 | PARTIAL — evaluates the string, never executes it | `do "go to next card"` does nothing |
| A7 | `convert <date> to <format>` | Interpreter.swift:1945 | NO-OP — args discarded | No date/time reformatting |
| A8 | `the clickChunk` / `clickH` / `clickV` / `clickLine` / `clickLoc` / `clickText` | Interpreter.swift:3193 | NO-OP | Click-position introspection always `""` |
| A9 | `the menus` / `the destination` | Interpreter.swift:3225 | NO-OP | Always `""` |

### Cluster A′ — Commands needing app-layer context (resolved by one provider)

These parse but no-op **because the interpreter has no handle on the application
shell.** This is exactly the problem `SystemProvider` already solved for audio.
A single new provider protocol resolves the whole group.

| # | Surface | Location | Worth doing? |
|---|---------|----------|--------------|
| A10 | `open stack "X"` | Interpreter.swift:1490 | Yes — real multi-stack navigation |
| A11 | `save stack` | Interpreter.swift:1950 | Yes — common authoring need |
| A12 | `close window` / `quit app` | Interpreter.swift:1950 | Yes |
| A13 | `edit the script of <object>` | Interpreter.swift:1950 | Yes — opens Script Editor |
| A14 | `print card` / `print field` | Interpreter.swift:2600 | Yes — genuinely useful |
| A15 | `doMenu "item"` | Interpreter.swift:2600 | Partial — map the common menu items only |

### Cluster A″ — Legacy cruft: leave as documented no-ops

No modern analog or actively undesirable. **Recommend: keep recognized, document
in `HypeTalkGuide` as intentional no-ops, do NOT implement.**

`dial`, `copy template`, `start using` / `stop using` stack, `disable` / `enable`
menu, `help`, `debug`, `clickAt` (synthetic mouse). (`read from file` /
`write to file` are deferred to Cluster-D security work, not here.)

### Cluster B — Apple-framework interaction depth

| # | Surface | Location | State |
|---|---------|----------|-------|
| B1 | Video part transport — scrubbing, playback rate, seek-from-script | CardCanvasView `updateVideoPlayers` | MINIMAL — only play/pause exposed |
| B2 | Paint import/export — `import paint` / `export paint` parse but no-op; runtime UI wiring incomplete | Interpreter.swift:2600; AST has the cases | PARTIAL — `PaintLayer` persists, command + UI path missing |

### Cluster C — Architectural-runway bets (intentionally parked; separate tracks)

Large, documented in `architecture.md §9`. **Not "finish the stubs" work** — each
is its own product decision. Listed for completeness, recommended to stay parked
until a concrete need lands.

- **C1 — Live Sync external transport.** `SyncService` has a working local
  operation/change-set engine but loopback-only; no CloudKit / Multipeer / server
  transport. Large; needs a collaboration-UX product decision first.
- **C2 — Full SpriteKit native card rendering (Phase C).** `CardSKScene.nativeLayer`
  + `ShapePartNode` / `ImagePartNode` exist as scaffolding; AppKit/CG overlays are
  still the primary render path for most part types. Large migration; current
  hybrid works.
- **C3 — Comprehensive XCMD/XFCN emulation.** HyperCard import emulates 2 externals
  (`SetCursor`, `ExternalVersion`), marks 7 known-unsupported, degrades the rest
  gracefully. Broadening coverage is niche, demand-driven.
- **C4 — HyperCard import WOBA bitmap decompression + PICT auto-placement.** Two
  legacy-format readers absent; imported stacks lose embedded paint/PICT art.
  Niche; only matters for art-heavy vintage stacks.

### Cluster D — Powerful primitives needing a security model

| # | Surface | Why grouped | 
|---|---------|-------------|
| D1 | `do <expr>` HypeTalk eval (also listed A6) | Arbitrary-code eval — needs the same gate discipline as the AI tool surface |
| D2 | `read from file` / `write to file` | Filesystem egress on script-supplied paths — needs path validation like `MeshyImageInput` already does |

---

## 3. Development plan — phased, each phase a full pipeline run

Each phase is independently shippable and follows the repo's standing pipeline
(Architect → Security → Builder → Security(code) → Tester → commit). Effort is
rough engineer-days for one focused contributor.

### Phase 1 — Document-only HyperTalk completeness — ✅ DONE (2026-05-29)
**Status: shipped on `feat/complete-stubs`** (+23 tests, `Phase1StubCompletionTests`).
`sort cards by <expr>` does per-card key eval + stable text/numeric sort + sortKey
rewrite. `convert <src> to <fmt>` covers the full HyperCard date/time keyword
vocabulary with container write-back, POSIX-locale deterministic. `push`/`pop card`
+ `the recent cards` use a bounded 50-entry history on `StackRuntime` with
`navigateToCard` wired end-to-end. Keyword grammar takes quoted-string keywords;
bare-keyword parser extension deferred (pre-existing parser limit, not a new stub).

**Scope:** A3 `sort cards`, A4 `push`/`pop`/`recent cards`, A7 `convert` date/time.
These touch only the document model + runtime card-history stack. No UI context,
no security surface — fully headless-testable, highest ROI per risk.
- `sort cards by <expr> [ascending|descending] [text|numeric|international]`:
  evaluate the key expr per card against the document, stably reorder `cards`.
- `push card` / `pop card`: add a bounded card-history stack to `StackRuntime`;
  `recent cards` reads it. Mirror the existing navigation-directive plumbing.
- `convert <container> to <format>`: implement the HyperCard date/time format
  vocabulary (`seconds`, `dateItems`, `short`/`long`/`abbreviated date`/`time`)
  over `Date` + `DateFormatter`.
- Tests: parser already accepts these; add interpreter-level behavior tests.

### Phase 2 — Text search & selection subsystem — ✅ DONE (2026-05-29)
**Status: shipped on `feat/complete-stubs`** (+24 tests, `Phase2FindSelectClickTests`).
`find "text"` does a real case-insensitive substring search across card + background
fields with wrap-around, sets found-text/chunk/field/line session state on
`StackRuntime`, and navigates to the matching card; the `the foundText`/`foundChunk`/
`foundField`/`foundLine` getters read it. `select <chunk> of <field>` records selection
state; `the selectedText`/`selectedChunk`/`selectedField`/`selectedLine` are fully live
(model + getters). click-position getters (`the clickH/V/Loc/Text/Chunk/Line`) record
on mouse-down in browse mode and read back. `the menus` reuses the Phase-3
`HostApplicationProvider` (`menuTitles()` → real NSApp main-menu titles); `the
destination` returns the stack name. Session state follows the Phase-1 runtime pattern.
**Follow-ups (documented, not stubs):** actual `NSTextView` range-highlight for `select`
is a UI-layer enhancement (the getters are correct without it); `the selectedButton` /
`the selectedLoc` remain `""` (need live radio-group / pixel state).

**Scope:** A1 `find` + found-* getters, A2 `select` + selected-* getters, A8
click-* getters, A9 `the menus`/`destination`.
- Build a `find` engine over field/card text honoring `find`, `find word`,
  `find chars`, `find whole`, `find string` variants; set `foundText` /
  `foundChunk` / `foundField` / `foundLine` and navigate to the matching card.
- `select` writes a selection model the field editor reads; the selected-*
  getters report it. Needs a small selection-state object on the runtime that the
  `CardCanvasView` field editor already-tracks-internally can publish back.
- click-* getters: capture last-click chunk/loc in the runtime on mouse events
  (the dispatcher already knows the hit part + point).
- This is the highest HyperCard-compat-value cluster; size it generously.

### Phase 3 — `HostApplicationProvider` — ✅ DONE (2026-05-29)
**Status: shipped on `feat/complete-stubs`** (+33 tests: 24 dispatch in
`Phase3HostApplicationProviderTests` + 9 real-provider security tests in
`AppKitHostApplicationProviderTests`). New `HostApplicationProvider` protocol
(no-op default + `StubHostApplicationProvider`) threaded through the single
interpreter init; `AppKitHostApplicationProvider` wired into all UI entry points.
Resolved: `lock`/`unlock screen` (real — canvas observes `.hypeScreenLock`/`Unlock`,
`draw()` early-returns while locked, forces redraw on unlock, observers removed on
dismantle), `open stack`, `save stack`, `close window`, `quit`, `edit script of`,
`print`, `doMenu`. **Security:** `doMenu` allowlist is strictly non-destructive
(navigation + copy/paste only; Delete Card/Cut/Clear/Delete Stack/New Card all
refused; `undo` dropped per code review — responder-chain undo could reverse the
user's own edits); `openStack` canonicalizes (`..` + symlink) before the `.hype`
guard (CWE-22); `print` caches the decoded doc by path+mtime to avoid main-thread
self-DoS in a loop. Code-stage security review: GO (3 findings all fixed inline).

**Scope:** A5 `lock`/`unlock screen`, A10 `open stack`, A11 `save stack`, A12
`close window`/`quit app`, A13 `edit script of`, A14 `print`, A15 `doMenu`.
**Architecture:** mirror `SystemProvider` exactly. Define a `HostApplicationProvider`
protocol in `Interpreter.swift`, give it a no-op default + a `Stub` for CLI/tests,
implement an `AppKitHostApplicationProvider` in the `Hype` target, and wire it into
the same three entry points the audio provider uses
(`AIChatPanel`/`NetworkPanelView`/`MessageBoxView`). Each command becomes a
one-line `await context.hostProvider.X(...)` call replacing the current `break`.
- `lock`/`unlock screen`: provider brackets a redraw-suppression flag on
  `CardCanvasNSView` (pairs with the `.onSetNeedsDisplay` policy already in place).
- `print`: `NSPrintOperation` over a rendered card image / field text.
- `doMenu`: map a curated allowlist of menu titles to existing command handlers
  (Go menu nav, Edit copy/paste) — NOT arbitrary menu reflection.
- One provider, one security review, the whole A′ cluster closes.

### Phase 4 — Powerful primitives + security model — ✅ DONE (2026-05-29)
**Scope:** D1 `do <expr>`, D2 `read`/`write file`.
- `do <expr>`: lex+parse the evaluated string and execute it in the current
  environment with the same instruction-limit + nesting-depth guards the main
  interpreter uses. Security pass mandatory — it's eval.
- `read`/`write file`: route paths through a validator modeled on
  `MeshyImageInput` (absolute-path, symlink-resolve, blocked-prefix, containment
  under a user-chosen sandbox root) + a per-stack `fileAccessAllowed` opt-in flag
  mirroring `meshyEnabled` / `webAssetsAllowed`. Full-tier pipeline.

**✅ DONE — Full-tier pipeline (Architect→Security(plan)→Builder→Security(code)→Tester).**
Critical discovery: `do`/`read`/`write` were never lexer keywords and the AST
cases (`.doBlock`/`.readCmd`/`.writeCmd`) were unreachable dead code — so this
added Token + Lexer + Parser support, not just interpreter logic.

- **`do <expr>`** (Interpreter `.doBlock`): evaluates the string then parses it
  as a **bare statement list** via the new `Parser.parseStatements()` (NO
  synthetic `on _doEval … end` wrapper — that approach was rejected by the
  plan-stage security review because `isEndOfHandler` is handler-name-blind, so
  a string containing `end _doEval` could break out and define extra handlers).
  `parseStatements()` rejects `.on`/`.function`/`.end` at top level. Runs inline
  in the current handler env (`do "put 5 into x"` mutates `x`; `do "go next"`
  navigates) sharing the SAME `instructionCount` budget; guarded by a dedicated
  `nestedEvalDepth` (cap 8, checked FIRST, independent of `nestedSendDepth`=32)
  and a 64 KB script-length cap (lex/parse runs outside the instruction budget).
  Parse errors surface as `ScriptError`, never crash.
- **`read from file "x"` / `write <expr> to file "x"`**: new `FileAccessProvider`
  protocol (HypeCore) — deny-by-default `StubFileAccessProvider` (nil root →
  `.accessDenied`) + `SandboxedFileAccessProvider(root:)` with a pure,
  unit-testable `resolveSandboxedURL` (reject empty/absolute/`..`; canonicalize
  both sides via `resolvingSymlinksInPath`; containment via `hasPrefix(root+"/")`;
  supplemental blocked-prefix list; 10 MB read/write caps with TOCTOU rechecks;
  write re-validates path after mkdir before atomic write). `read` puts whole
  file into `it`; `write` overwrites atomically. App-layer
  `AppKitFileAccessProvider` supplies a per-stack sandbox
  `~/Library/Application Support/Hype/StackFiles/<stackId>/` (0o700). Gated by a
  per-stack `Stack.fileAccessAllowed` flag (default false, `decodeIfPresent`),
  wired at all 6 provider call-sites as
  `flag ? AppKitFileAccessProvider(stackId:) : StubFileAccessProvider()`. Error
  messages never leak resolved paths.
- **Security code review found 1 medium defect, fixed inline:** the interpreter's
  `.send` dispatch omitted `fileProvider` *and* `hostProvider` (Phase 3) — so a
  handler reached via `send` silently got the deny/no-op stubs. Both now
  propagate through `MessageDispatcher.dispatchAsync`; +1 regression test.
- **Tests:** +46 (`Phase4DoEvalTests` 24 + `Phase4FileAccessTests` 22 incl. the
  send-propagation regression). Full suite 2453 tests; only the pre-existing
  `HypeTalkGuide` 64 KB-budget failure remains red (untouched by this branch;
  resolved at end-of-run when the new commands are documented).
- **Documented follow-ups:** (1) the per-handler instruction budget resets on
  `send` (pre-existing interpreter-wide property, bounded by `nestedSendDepth`,
  cancellable — out of Phase 4 scope; a global shared-budget propagation is a
  separate hardening track); (2) cloned stacks inherit the same `stackId` and so
  share a sandbox directory (documented in `SandboxedFileAccessProvider`).

### Phase 5 — Framework-depth finishers — ✅ DONE (2026-05-29)
**Scope:** B1 video transport, B2 paint import/export.
- Video: expose `the currentTime` / `set the playRate` / `seek` on video parts via
  the `AVPlayer` already hosted; add transport getters/setters to the property
  dispatch.
- Paint: wire `import paint "file"` / `export paint "file"` to the existing
  `PaintLayer` + the Phase-4 file-access provider (depends on Phase 4).

**✅ DONE — Architect→Builder→Security(code)→Tester (paint import is file I/O on
untrusted input; the egress sandbox was inherited verbatim from Phase 4 so the
novel surface was just the PNG decode).** First reconciled with origin branch
`codex/imported-paint-layer-assets` — it's already merged into origin/main (our
base) and is orthogonal (HyperCard-import asset classification, not the
`import paint`/`export paint` commands), so no conflict.

- **Video transport** (B1, Lite tier): 3 backward-compat `Part` fields
  (`videoCurrentTime`/`videoDuration`/`videoPlayRate`, defaults 0/0/1). Interpreter
  getters `the currentTime`/`the playRate`/`the duration` (duration now three-way:
  video→`videoDuration`, appleMusic→`musicDuration`, else `audioDuration`) and
  setters for currentTime (clamped ≥0) + playRate. The canvas
  (`CardCanvasView.updateVideoPlayers`) is the apply+report layer: applies rate +
  script-originated seeks to the `AVPlayerView`, and a `addPeriodicTimeObserver`
  reports live `currentTime`/`duration` back to the Part. A **seek-epoch sentinel**
  prevents the report→seek feedback loop; observers are removed before every player
  release (all 4 teardown paths) to avoid the AVFoundation crash.
- **Paint import/export** (B2): `exportPaint`/`importPaint` AST cases existed and
  the parser produced them but the interpreter no-op'd them. Now: `FileAccessProvider`
  gained binary `readData`/`writeData` (the canonical sandbox path; the text
  `readFile`/`writeFile` are re-expressed over them — one containment path, no
  Phase-4 regression). New AppKit-gated `PaintImageCodec` (RGBA↔PNG) reusing
  `PaintLayer.pngData()` for encode and a new `NSBitmapImageRep`→RGBA decode.
  `export paint "f"` writes the card's `CardPaintLayer` (1×1 transparent if unpainted);
  `import paint "f"` reads+decodes+`setPaintLayer` and busts the canvas paint cache
  so it redraws. All gated by Phase 4's `fileAccessAllowed` + sandbox.
- **Security:** the untrusted PNG decode is bounded by a **decompression-bomb cap**
  (reject >4096/side or >maxPixelCount **on `rep.pixelsWide/pixelsHigh` BEFORE the
  `cgImage` allocation** — review Finding 1), the inherited 10 MB byte cap, nil-on-
  failure (no force-unwraps), traversal/symlink/opt-in inherited from Phase 4, no
  path leak in errors, fail-closed when the flag is off, and a throwing `#else` on
  non-AppKit. Code review also clamped `playRate` to ±4 rejecting NaN/Inf (Finding 2).
- **Tests:** +33 (`Phase5PaintIOTests` 19 incl. codec round-trip / bomb / corrupt /
  oversize / traversal / flag-off; `Phase5VideoTransportTests` 14 incl. property
  round-trips, duration disambiguation, decode defaults, and the playRate-clamp
  regression). Full suite 2486 tests; only the pre-existing `HypeTalkGuide` 64 KB
  failure remains. Background paint layers stay out of scope (no model for them).

### Phase 6 — On-demand Apple frameworks — ⏸️ INTENTIONALLY DEFERRED (per plan) (2026-05-29)
ContactsUI, EventKit events, OAuth (WebAuthenticationServices), UserNotifications,
AVKit PiP, CoreLocation user-location. **Do not build speculatively.** Each is a
clean ≈1–2 day add when a real stack needs it; the roadmap doc already scopes them.

**Decision (autonomous, evidence-based):** confirmed via grep that NONE of these six
are partial stubs — there are zero AST/parser cases or provider hooks for
contact/event/oauth/notification/PiP/user-location anywhere in `Sources/`. (The only
CoreLocation usage is `MapLocationGeocoder`/`MapGeocodeCache` — address→coords
geocoding for the map part, which is complete, not device user-location.) So there is
no stub here to *finish*; these are entirely greenfield framework integrations.

Per this plan's own directive they remain **demand-driven**: each pulls in
entitlements, an Info.plist privacy-usage string, a runtime authorization prompt, and
(for Contacts/CoreLocation) PII surface or (for OAuth/WebAuthenticationServices) a
credential+network surface. Building them speculatively — with no stack requiring
them — would add risk and maintenance with zero current user value, and would violate
the "do not build speculatively" guidance. They will be implemented one at a time,
behind the established provider + per-stack opt-in pattern, when a concrete stack
creates the demand signal. **Phases 1–5 closed every genuinely user-facing stub.**

### Explicitly parked (Cluster C) — revisit only on demand
C1 Live Sync transport, C2 full SpriteKit native rendering, C3 broad XCMD
emulation, C4 WOBA/PICT import. Each is a multi-week architectural track, not
stub-finishing. Leave as documented runway.

---

## 4. Suggested sequencing & rationale

```
Phase 1  (document-only)        ── ship first: highest ROI, zero risk, headless tests
   │
Phase 3  (HostApplicationProvider) ── unblocks the largest stub cluster with one protocol
   │                                  (can run parallel to Phase 2)
Phase 2  (find/select subsystem)   ── highest HyperCard-compat value, larger surface
   │
Phase 4  (do-eval + file I/O)      ── gated on a security model; depends on nothing above
   │
Phase 5  (video + paint)           ── paint depends on Phase 4's file provider
   │
Phase 6  (on-demand frameworks)    ── demand-driven, not speculative
```

Phases 1–5 total ≈ **14–20 engineer-days** and close every genuinely user-facing
gap. Cluster C stays parked. Cluster A″ legacy cruft gets documented, not built.

## 5. Immediate next step (independent of the above)

The completed-but-uncommitted **audio/system-provider workstream** on disk should
be committed and pushed — it is finished work (`AppKitSystemProvider` fully wired)
sitting in the working tree, and it establishes the exact provider pattern Phase 3
will reuse.
