# Design: Turtle drawing publish gating

## Actor

Driving session (Opus) — focused perf chore; architecture self-recorded.

## Context

Verified in `Sources/HypeCore/Script/Interpreter.swift` (2026-08-20):

- Per-statement publish decision: `executeStatementAndPublish` (line ~907)
  calls `publishDocument` iff `statementProducesVisibleEffect(stmt)`.
  `statementProducesVisibleEffect` is called from ONLY this one site.
- Turtle commands are `.externalCommand(name, args)` and fall to the
  `default → true` arm (line ~855), so every one publishes.
- `StackRuntime.publishDocument` (line ~881) assigns the document and posts a
  main-actor `.stackRuntimeDocumentDidChange` notification → a whole-card
  re-render. The interpreter side is a cheap `Task.yield`; the cost is the
  app-side redraw, paid once per publish.
- The turtle execution path is synchronous and already knows whether a
  command changed rendered content: `applyTurtleOutcome` (line ~1268)
  computes `changed = !appended.isEmpty || outcome.deletesTurtleParts` (it
  guards `invalidatePartLookupCache()` on exactly this).
- Turtle verb dispatch normalizes the name as `name.lowercased()` (line
  ~2565) before `TurtleVocabulary.command(verb:args:)`; user `on <verb>`
  handlers shadow the built-in (dispatch precedence) — in that case the
  turtle engine is NOT invoked for that statement.
- A `CountingRuntime` test double already exists
  (`Tests/HypeCoreTests/InterpreterPublishGatingTests.swift`) that counts
  `publishDocument` calls — the exact benchmark instrument.

## Decision

Route the turtle-verb publish decision through the "did rendered content
change" signal the engine already computes, instead of the blanket
`.externalCommand → true`.

1. **`Environment` gains `var turtleDidRender: Bool = false`** — a
   per-statement signal.
2. **`applyTurtleOutcome` assigns it**: `let changed = !appended.isEmpty ||
   outcome.deletesTurtleParts; if changed { env.invalidatePartLookupCache() };
   env.turtleDidRender = changed`.
3. **`executeStatementAndPublish`**: reset `env.turtleDidRender = false` at
   the top (before `executeStatement`), so a shadowed `on <verb>` handler
   that never touches the turtle leaves the flag false. Then decide:
   ```swift
   let shouldPublish: Bool
   if case .externalCommand(let name, _) = stmt,
      TurtleVocabulary.isTurtleVerb(name.lowercased()) {
       shouldPublish = env.turtleDidRender
   } else {
       shouldPublish = statementProducesVisibleEffect(stmt)
   }
   ```
   Publish when `shouldPublish`; otherwise `Task.checkCancellation()` +
   `Task.yield()` (the existing pure-compute path).

### Why this is behavior-preserving

- A shape command (`circle`/`arc`/`dot`) and a stroke flush (`penUp`, a pen
  color/width change, `beginFill`, navigation, run end) emit a part →
  `turtleDidRender = true` → publishes exactly as before, so per-shape
  animation (`... circle 5 / wait ...`) and flush visibility are preserved.
- A buffered stroke that has NOT flushed produced no document change even
  pre-fix, so the pre-fix publish for `forward` rendered nothing new;
  removing it changes nothing visible.
- State-only commands (`penUp`/`penDown`/`right`/`left`/`setHeading`, pen-up
  moves, a color/width set with no open stroke) never changed the card;
  their publishes were pure waste.
- Shadowed `on <verb>`: the user handler runs as its own nested run and
  publishes its own visible changes through its own
  `executeStatementAndPublish`; the outer verb statement's publish was
  redundant, and the reset keeps `turtleDidRender` false so it is correctly
  skipped (no double or missing publish).
- End-of-run flush parts render when the handler's final document is applied
  by the runtime, unchanged.

Scope: turtle `.externalCommand` verbs only (the reported hot path — the
flower is entirely verbs). Turtle property SETs (`set … of the turtle`) and
`reset turtle` keep their current (rare, non-loop) publish behavior; noted
as a possible future micro-opt, out of scope here.

### D2. Gate the stray `repeat N times` "times" no-op (found in Build)

Verified via the publish-count benchmark: a `repeat N times` loop body begins
with `expressionStatement(.literal("times"))` — the trailing `times` token
the parser (`parseRepeatStatement` bare-count branch) never consumes, so
`parseRepeatBody` reads it as the loop's first body statement. It is a
harmless interpreter no-op (the same artifact `TurtleProgramValidator`'s
`strippingTimesArtifact` already tolerates), BUT it hit
`statementProducesVisibleEffect`'s `default → true`, so EVERY `repeat N times`
loop published once per iteration — the actual dominant cost in the flower
(12 of its 25 pre-D2 publishes) and a general, pre-existing perf bug for all
`repeat N times` loops (the existing publish-gating tests use `repeat with`,
which has no artifact, so they never caught it).

Fix: add a `case .expressionStatement(let expr)` to
`statementProducesVisibleEffect` that returns `false` when `expr` is a
`.literal` (a bare constant has no side effect and can never be visible),
and `true` otherwise (call/property-read expression statements may have
effects). This removes the per-iteration redraw from every `repeat N times`
loop, not just turtle ones. The root cause (parser not consuming `times`) is
out of scope for a publish-gating chore and is filed as a separate cleanup;
fixing it there would also let `TurtleProgramValidator` drop
`strippingTimesArtifact`.

Combined effect on the canonical flower: ~99 → ~13 publishes (clean + 12
circle stamps).

## Risks / Trade-offs

- The one real risk is suppressing a publish that SHOULD happen (a turtle
  command that changed rendered content but didn't set the flag) → a drawing
  that doesn't appear. Mitigated: the flag is set from the SAME signal that
  already guards `invalidatePartLookupCache` (the established "rendered parts
  changed" predicate), and the benchmark asserts shapes still publish.
- No new shared state, no concurrency change: `turtleDidRender` is a plain
  `Bool` on the per-run `Environment` value.

## Test plan

`Tests/HypeCoreTests/InterpreterPublishGatingTests.swift` (existing suite,
`CountingRuntime`):
- **Benchmark**: the canonical flower (`clean` + `home` + `setPenColor` +
  12×`penUp/forward/penDown/circle/penUp/back/penDown/right`) publishes at
  most ~one redraw per drawn shape (assert `count <= 20`, and `>= 12` so we
  know shapes still publish), and the document ends with 12 turtle path
  parts (drawing unchanged). Comment records the pre-fix count (~99).
- **Stroke control**: a pen-down square (`forward/right` ×4) still ends with
  exactly one `turtle path` part (behavior preserved) and does not publish
  per state-only command.
- **Shape-animation preserved**: a loop of `circle` (each emits) publishes
  once per circle (so `wait`-driven turtle animation still shows each shape).

## Conditions for Builder

1. **Gate turtle-verb publishing on the real render signal.**
   `turtleDidRender` is set from `!appended.isEmpty ||
   outcome.deletesTurtleParts` in `applyTurtleOutcome` and is the ONLY thing
   that changes for the turtle-verb publish decision. Do not alter
   `statementProducesVisibleEffect`'s existing (non-turtle) behavior.
2. **Reset per statement.** `env.turtleDidRender = false` before
   `executeStatement` in `executeStatementAndPublish`, so a shadowed
   `on <verb>` handler (turtle engine not invoked) is never mis-read as a
   turtle render.
3. **Turtle-verb detection matches dispatch.** Use
   `TurtleVocabulary.isTurtleVerb(name.lowercased())` — the same
   normalization the dispatcher uses (`name.lowercased()`).
4. **Strictly behavior-preserving.** Emitted shapes and stroke flushes still
   publish; drawings are byte-identical. Add the benchmark + the two controls
   above; the whole existing suite (esp. `InterpreterPublishGatingTests` and
   the turtle tests) stays green.
5. **No new shared/concurrent state** and no change to `publishDocument`,
   `StackRuntime`, or the turtle engine/applier.
