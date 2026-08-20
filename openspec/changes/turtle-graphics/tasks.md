# Tasks — turtle-graphics

## 1. P1 — Engine, number canon, colors (ends green)

- [x] 1.1 Create `Sources/HypeCore/Script/HypeTalkFormat.swift`
      (`number(_:)`, `number(from:)`, `isTruthy(_:)`); delegate
      `Interpreter.formatNumber` / `toNumber` / `isTruthy` to it
      (byte-identical behavior).
- [x] 1.2 Create `Sources/HypeCore/Script/TurtleEngine.swift`: `Canvas`,
      `ScalarState` (+ `encoded`/`init?(encoded:)`), `Command`,
      `Emission`/`FrameRect`, `Outcome`, `TurtleError` (LocalizedError),
      `ErrorCopy` (all E-strings), limits, `perform`, `endRun`,
      `propertyValue`, `setProperty`, cardinal-snapped trig, §5.4
      circle/arc, §5.1 frame math, §5.5 atomic limit checks.
- [x] 1.3 Add `TurtleVocabulary` (verb map incl. abbreviations,
      `zeroArgumentVerbs`, `isTurtleVerb`).
- [x] 1.4 Create `Sources/HypeCore/Script/TurtlePartApplier.swift`
      (deletion by prefix, smallest-free-N naming, sortKey via
      `nextPartSortOrdinal`); change `nextPartSortOrdinal` in
      `Sources/HypeCore/Models/PartDuplication.swift` to `internal`.
- [x] 1.5 Extend `Sources/HypeCore/Models/HexColor.swift` with the 16-name
      table (17 keys with `grey`), lookup after the empty check, before hex.
- [x] 1.6 Write `Tests/HypeCoreTests/TurtleEngineTests.swift` (criteria
      1–3, 5–9, engine half of 15, encoding round-trip, limits).
- [x] 1.7 Extend `Tests/HypeCoreTests/PartPropertyDispatchTests.swift`
      for named colors (criterion 19 unit level) + garbage-still-errors.
- [x] 1.8 `swift test` green.

## 2. P2 — HypeTalk front-end (ends green)

- [x] 2.1 Parser gates in `Sources/HypeCore/Script/Parser.swift`:
      zero-arg turtle verbs in `isKnownZeroArgumentExternalCommand`;
      turtle verbs in `isKnownExternalCommand`; `.minus` lookahead gated
      on `TurtleVocabulary.isTurtleVerb` in
      `shouldParseExternalCommandStatement`.
- [x] 2.2 Interpreter: add `Environment.turtle`; turtle leaf helpers
      (`turtleEngine`, `syncTurtle`, `applyTurtleOutcome`,
      `executeTurtleCommand`, `flushTurtleAtRunEnd`,
      `flushTurtleForNavigation`).
- [x] 2.3 Intercepts: `.externalCommand` (after user-handler dispatch,
      before classic builtins); `.resetCmd` turtle branch (bare-word
      fallback); `.set` turtle-target branch; `evaluateProperty`
      turtle-target branch.
- [x] 2.4 Flush hooks: all `executeAsyncImpl` exit paths that return a
      document (normal, passMessage, exitHandler, showAllCards,
      cancelled); navigation flush at `.go`, `.goInStack`, `.pop`.
- [x] 2.4b **(Security C13)** Add the per-iteration
      `instructionCount += 1` + `try context.checkCancellation()` +
      `instructionLimit` guard (as `.repeatForever` already has) to the
      `.repeatCount` and `.repeatWith` loop heads
      (`Interpreter.swift:1763–1841`), so empty-/non-emitting-body counted
      loops are bounded and cancellable.
- [x] 2.5 Write `Tests/HypeCoreTests/TurtleScriptingTests.swift`
      (criteria 1, 3, 4, 11–13, interpreter half of 15, REPL walk,
      navigation flush, `on forward` shadowing; capturing runtime double
      for E8 partial state).
- [x] 2.6 Extend `Tests/HypeCoreTests/InterpreterFuzzTests.swift`: turtle
      statement family in the grammar fuzzer + metamorphic relations
      (`right d`/`left d`, `fd n`/`bk n`, mod-360, square closure, `clean`
      idempotence); **(Security A2)** deeply-nested + ~64 KB adversarial
      programs assert no crash; **(Security C13)** a huge-count empty-body
      `repeat` terminates with "Instruction limit exceeded". Suite green
      (criterion 20).
- [x] 2.7 `swift test` green.

## 3. P3 — AI front-end (ends green)

- [ ] 3.1 Create `Sources/HypeCore/Script/TurtleProgramValidator.swift`
      (64 KB cap, real Lexer/Parser, structural allowlist, token-segment
      line cursor, E9 composition via `TurtleEngine.ErrorCopy`).
      **(Security C4)** The allowed-expression validator runs on EVERY
      expression position — external-command args, the `set` value
      expression, and the `.repeatCount` count and `.repeatWith` from/to
      bounds — not just args/bodies; `functionCall` in any position refuses
      with E9.
- [ ] 3.2 `Sources/HypeCore/AI/HypeTools.swift`: `draw_with_turtle` tool
      (§7.1 description, required `program`); add to
      `cardControlAuthoringTools` and `spriteSceneAuthoringTools`
      allowlists. Runtime catalog untouched.
- [ ] 3.3 `Sources/HypeCore/AI/HypeToolExecutor.swift`:
      `case "draw_with_turtle"` → `executeDrawWithTurtle` (validate →
      snapshot → synthetic Handler → `Interpreter.executeAsync` → apply
      `modifiedDocument` on success only → §7.1 summary; error strings
      verbatim). **(Security C14)** Construct the `ExecutionContext` with
      deny-by-default stub providers only (`StubFileAccessProvider`,
      `StubHostApplicationProvider`, `StubAIScriptingProvider`,
      `runtimeProvider: nil`).
- [ ] 3.4 Write
      `Tests/HypeCoreTests/TurtleCrossSurfaceEquivalenceTests.swift`
      (criteria 16, 17, 18 — §8 garden program, byte-identical part
      fields, identical E1 string, E9 zero-parts, catalog
      presence/absence, size cap). **(Security C4)** escape cases:
      `repeat foo() times`, `repeat with i = 1 to foo()`,
      `set the heading of the turtle to foo()` each refuse E9, zero parts.
      **(Security C14)** a shadowed `on forward` handler doing
      `write … to file` is denied by the stub file provider.
- [ ] 3.5 `swift test` green.

## 4. P4 — Renderers and discovery (ends green)

- [ ] 4.1 `Sources/HypeCore/Rendering/RenderGeometry.swift`:
      `freeformIsOpenStroke(_:)` + `freeformLocalPoints(_:)` (public).
- [ ] 4.2 `Sources/HypeCore/Rendering/ShapeRenderer.swift` `.freeform`:
      shared contract, no y-flip, round caps/joins, open vs closed
      branches.
- [ ] 4.3 `Sources/Hype/SpriteKit/ShapePartNode.swift` `.freeform`: shared
      contract ((x, −y) locals, `.clear` fill on open branch, round
      caps/joins).
- [ ] 4.3b `Sources/HypeCore/Export/TargetRuntimeControlViews.swift`
      `TargetRuntimeShapeView.shapePath`/`body` `.freeform`: gate
      `closeSubpath()` (line 1299) and the `context.fill(...)` (line 1263)
      on `!RenderGeometry.freeformIsOpenStroke(part)`; stroke `.round`
      cap/join when `strokeWidth > 0`. Keep `normalizedPathPoints` scaling
      unchanged (N3).
- [ ] 4.4 Write `Tests/HypeCoreTests/ShapeRendererFreeformTests.swift`,
      `Tests/HypeCoreTests/TargetRuntimeFreeformTests.swift`, and
      `Tests/HypeTests/ShapePartNodeFreeformTests.swift` (criterion 10
      across all three sites — `fillColor ""` open+unfilled vs `#FFFFFF`
      closed+filled legacy regression; criterion 14 for CG/SK only).
- [ ] 4.5 `Sources/HypeCore/AI/HypeTalkGuide.swift`: `## Turtle graphics`
      section (§4 vocabulary, defaults, part contract, error copy, R12
      note).
- [ ] 4.6 `Sources/HypeCore/AI/HypeTalkSkillCatalog.swift`: skill
      `turtle_graphics` (case, descriptor, guidance bullets, one pattern).
- [ ] 4.7 Extend `Tests/HypeCoreTests/HypeTalkGuideTests.swift` (section +
      verbs present; skill listed).
- [ ] 4.8 Full `swift test` green.

## 5. Later phases (not Build)

- [ ] 5.1 Documentation phase: `HypeTalk-LLM-Context.md` turtle section
      (strict subset of the guide); Turtle Garden example stack for the
      Tester (design-mock §8).
- [ ] 5.2 Design Review: rule on deviations d1–d14 in `design.md`.
