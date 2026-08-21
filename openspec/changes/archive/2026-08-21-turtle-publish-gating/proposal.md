# Turtle drawing: publish only when a shape changes

## Why

Turtle drawing is slow. Each turtle command is a generic `.externalCommand`,
which the interpreter's publish gate classifies as visible-effect
(`statementProducesVisibleEffect`, `default → true`), so **every** turtle
command calls `publishDocument` — a main-actor
`.stackRuntimeDocumentDidChange` notification and a full-card re-render
(`StackRuntime.publishDocument`). But most turtle commands change no rendered
content: `penUp`, `penDown`, `right`/`left`/`setHeading`, and pen-up
`forward`/`back` only move or rotate the turtle. A 12-circle "flower" runs
~99 turtle commands and pays for ~99 full-card redraws when only ~13 actually
draw or clear a shape.

## What Changes

- Turtle `.externalCommand` verbs publish **only when they actually changed
  rendered content** — a shape part was emitted, or turtle parts were cleared
  (`clean`/`clearScreen`). `applyTurtleOutcome` already computes exactly this
  (`!appended.isEmpty || outcome.deletesTurtleParts`); the fix records it on
  the environment and routes the per-statement publish decision through it
  for turtle verbs. State-only turtle commands become pure-compute (yield, no
  redraw), like the existing pure-compute gating for arithmetic/variable
  writes.
- Strictly behavior-preserving: the drawing is byte-identical; shapes still
  publish when drawn (so per-shape animation with `wait` is preserved) and
  buffered strokes still appear at their flush points exactly as before. Only
  the wasteful redraws for state-only commands are removed. `lock screen`
  still collapses a whole drawing to one redraw.
- **Also fixes a general (non-turtle) perf bug found while building this:**
  the `repeat N times` parser leaves a stray `expressionStatement(.literal
  ("times"))` as the loop's first body statement (a harmless no-op — the same
  artifact the turtle validator already tolerates). It was classified
  visible-effect (`default → true`), so **every `repeat N times` loop
  published once per iteration** regardless of body. A bare-literal
  expression statement has no visible effect, so it is now gated out — a
  redraw-per-iteration removed from every counted loop in the app. (The
  existing publish-gating tests never caught this: they use `repeat with`,
  which has no `times` artifact.) The root parser cause is filed as a
  separate cleanup.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

_None — a performance change to the interpreter's per-statement publish
gating. No documented capability, output, or vocabulary changes._

## Impact

- `Sources/HypeCore/Script/Interpreter.swift` — `Environment` gains a
  per-statement `turtleDidRender` flag; `applyTurtleOutcome` sets it;
  `executeStatementAndPublish` gates turtle-verb publishing on it.
- `Tests/HypeCoreTests/InterpreterPublishGatingTests.swift` — a benchmark
  test asserting the flower publishes ~one redraw per drawn shape (not per
  command), plus a control that a pen-down stroke still renders.

Measured effect (publish count for the canonical flower): ~99 → ~13.
