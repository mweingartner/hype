# Tasks — repeatwhile-instruction-guard

## 1. Fix (ends green)

- [ ] 1.1 In `Sources/HypeCore/Script/Interpreter.swift`, `.repeatWhile`
      case: insert the per-iteration guard (`instructionCount += 1` +
      `instructionLimit` throw of "Instruction limit exceeded") immediately
      after `if !isTruthy(condValue) { break }`, before the profiler call —
      byte-identical to the `.repeatCount`/`.repeatWith` guard.
- [ ] 1.2 Add tests to `Tests/HypeCoreTests/InterpreterFuzzTests.swift`:
      (a) `repeat while true` with an empty body terminates with
      "Instruction limit exceeded"; (b) a normally-terminating `repeat while`
      still completes without falsely hitting the limit.
- [ ] 1.3 `bash scripts/mpd-test.sh` green.
