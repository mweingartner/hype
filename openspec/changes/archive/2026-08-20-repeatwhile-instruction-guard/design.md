# Design: repeat while instruction-limit guard

## Actor

Driving session (Opus) — trivial defect fix; architecture self-recorded.

## Context

Verified in `Sources/HypeCore/Script/Interpreter.swift` (2026-08-20):

- Four repeat loop heads in the statement executor:
  - `.repeatForever` (~line 1913) — guarded (`instructionCount += 1` +
    `instructionLimit` throw at ~1915–1917).
  - `.repeatCount` (~line 1935) — guarded at ~1946–1948 (Security C13).
  - `.repeatWhile` (~line 1966) — **NOT guarded**. Its `while true` loop
    evaluates the condition, breaks if not truthy, records the profiler,
    then runs the body — with no per-iteration `instructionCount` increment.
  - `.repeatWith` (~line 1986) — guarded at ~2011–2013 (Security C13).
- The canonical guard (from `.repeatCount`, lines 1946–1948):
  ```swift
  instructionCount += 1
  if instructionCount > context.instructionLimit {
      throw ScriptError(message: "Instruction limit exceeded", line: handler.line, handler: handler.name)
  }
  ```
- `executeStatementAndPublish` increments `instructionCount` per body
  statement, so a NON-empty body is already bounded; the gap is only the
  empty-/non-emitting-body case, which the loop head must count.

## Decision

Insert the canonical guard in the `.repeatWhile` case immediately AFTER the
`if !isTruthy(condValue) { break }` line and BEFORE
`context.profiler?.recordLoopIteration("repeatWhile")`. Placing it after the
break means a loop whose condition becomes false exits WITHOUT consuming an
extra instruction count, and only iterations that will actually execute the
body are counted — matching the semantics of the other three forms. The
guard text is byte-identical to `.repeatCount`/`.repeatWith`. No other change
to `.repeatWhile` semantics.

## Risks / Trade-offs

- A legitimately long-running `repeat while` that stays under
  `context.instructionLimit` (default 1,000,000) is unaffected — the guard
  only fires when the *same* global limit that already bounds every other
  loop form is exceeded. Any existing test with a bounded `repeat while`
  stays green.
- No new attack surface: the change only ADDS a termination bound (strictly
  safer). Not reachable via `draw_with_turtle` (validator excludes
  `repeat while`), so no cross-surface impact.

## Test plan

`Tests/HypeCoreTests/InterpreterFuzzTests.swift`:
- `repeat while true` with an empty body terminates with a `ScriptError`
  whose message is "Instruction limit exceeded" (run on a bounded harness so
  a regression would hang the test, catching a missing guard).
- A `repeat while` that terminates normally within the limit still completes
  and produces its expected effect (guard doesn't cause a false positive).

## Conditions for Builder

1. **Match the existing guard exactly** — `instructionCount += 1` then
   `if instructionCount > context.instructionLimit { throw ScriptError(message: "Instruction limit exceeded", line: handler.line, handler: handler.name) }`, byte-identical to lines ~1946–1948.
2. **Placement**: immediately after `if !isTruthy(condValue) { break }` and
   before the profiler call, so a false condition exits without counting and
   only executing iterations increment the counter.
3. **No other semantic change** to `.repeatWhile` (condition eval, body
   execution, exit/next-repeat control signals unchanged).
4. **Add the two tests** above; the empty-body test must actually exercise
   the guard (assert the exact "Instruction limit exceeded" message).
5. **No regression**: every existing `repeat while` test stays green — a
   normally-terminating loop must not falsely hit the limit.
