# Tasks — turtle-publish-gating

## 1. Fix (ends green)

- [ ] 1.1 `Sources/HypeCore/Script/Interpreter.swift`: add
      `var turtleDidRender: Bool = false` to `Environment`.
- [ ] 1.2 `applyTurtleOutcome`: set `env.turtleDidRender = !appended.isEmpty
      || outcome.deletesTurtleParts` (keep `invalidatePartLookupCache()`
      guarded on the same condition).
- [ ] 1.3 `executeStatementAndPublish`: reset `env.turtleDidRender = false`
      before `executeStatement`; gate the publish so a turtle
      `.externalCommand` verb (`TurtleVocabulary.isTurtleVerb(name.lowercased())`)
      publishes iff `env.turtleDidRender`, else uses
      `statementProducesVisibleEffect(stmt)` unchanged.
- [ ] 1.4 (D2) `statementProducesVisibleEffect`: add
      `case .expressionStatement(let expr)` returning `false` for a
      `.literal` expr — gates the stray `repeat N times` "times" no-op so
      `repeat N times` loops no longer publish once per iteration.
- [ ] 1.5 `Tests/HypeCoreTests/InterpreterPublishGatingTests.swift`: add the
      flower benchmark (publishes ≤ ~20, ≥ 12; 12 parts drawn), a state-only
      turtle loop (0 publishes), a pen-down square control (one part), and a
      per-shape animation check (≥ one publish per drawn shape).
- [ ] 1.6 `bash scripts/mpd-test.sh` green.
