# repeat while instruction-limit guard

## Why

The HypeTalk interpreter's `.repeatWhile` loop head
(`Interpreter.swift`) lacks the per-iteration `instructionCount` /
`instructionLimit` guard that `.repeatForever`, `.repeatCount`, and
`.repeatWith` all have (the latter two gained it in the turtle-graphics
change, commit 3be1180, Security condition C13). So a script like
`repeat while true` with an empty or non-emitting body executes zero body
statements, never increments `instructionCount` (the per-statement guard in
`executeStatement` never fires on an empty body), and spins **unbounded and
uncancellably** — hanging the app. Three of the four repeat forms are
bounded; one is not.

## What Changes

- Add the identical per-iteration guard to the `.repeatWhile` loop head,
  placed after the condition's break-check so a false condition still exits
  cleanly and only executing iterations are counted, matching
  `.repeatCount`/`.repeatWith` byte-for-byte.
- Add a test asserting `repeat while true` with an empty body terminates
  with "Instruction limit exceeded" rather than hanging, and that a
  normally-terminating `repeat while` still completes.

No behavior change for any loop that terminates within `instructionLimit`.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

_None — this is a defect fix that aligns `.repeatWhile` with the existing,
already-intended instruction-limit bound the other three repeat forms
enforce. No documented capability changes._

## Impact

- `Sources/HypeCore/Script/Interpreter.swift` — the `.repeatWhile` case.
- `Tests/HypeCoreTests/InterpreterFuzzTests.swift` — a termination test.

Severity: low under the local-trusted-user threat profile (reachable only
by a trusted stack author; NOT reachable via the `draw_with_turtle` AI tool,
whose validator excludes `repeat while`). It is a consistency/robustness fix
completing the C13 invariant across all four repeat forms.
