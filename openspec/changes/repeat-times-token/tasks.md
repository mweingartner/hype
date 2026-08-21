# Tasks — repeat-times-token

## 1. Fix (ends green)

- [ ] 1.1 `Sources/HypeCore/Script/Parser.swift`: in `parseRepeatStatement`'s
      bare-count branch, `if current.type == .times { _ = advance() }` after
      the count expression, before `skipNewlines()`.
- [ ] 1.2 `Sources/HypeCore/Script/TurtleProgramValidator.swift`: remove
      `strippingTimesArtifact` (function + doc) and validate the `.repeatCount`
      body directly (`refusal(forStatements: body, …)`).
- [ ] 1.3 Add `Tests/HypeCoreTests/RepeatTimesParsingTests.swift`: a
      `repeat N times` body has exactly one statement (no stray `times`);
      `repeat N` (no `times`), `repeat for N times`, and a nested
      `repeat N times` all parse to clean bodies.
- [ ] 1.4 `bash scripts/mpd-test.sh` green — esp. TurtleCrossSurfaceEquivalence
      (E9 line numbers, garden equivalence), TurtleScripting, InterpreterFuzz
      (turtle grammar/metamorphic), and repeat-N-times interpreter counts.
