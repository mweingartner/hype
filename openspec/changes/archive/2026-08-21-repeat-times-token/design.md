# Design: repeat N times — consume the trailing `times`

## Actor

Driving session (Opus) — small parser defect fix; architecture self-recorded.

## Context

Verified in `Sources/HypeCore/Script/Parser.swift` (2026-08-21):

- `parseRepeatStatement` bare-count branch (~lines 1020-1027):
  ```swift
  if current.value.lowercased() == "for" { _ = advance() }
  let count = try parseExpression()
  skipNewlines()
  let body = try parseRepeatBody()
  return .repeatCount(count: count, body: body)
  ```
  After `parseExpression()` parses the count, the next token is `.times`
  (`Lexer.swift:41` maps `"times"` → `.times`); nothing consumes it, so
  `parseRepeatBody` parses it as `.expressionStatement(.literal("times"))`
  (the `.times` case in the expression parser yields the literal).
- The other repeat forms already consume their keywords with `advance()`
  (`while`/`until` at ~996/1005, `for` at ~1021).
- `TurtleProgramValidator.strippingTimesArtifact` (`TurtleProgramValidator.swift`
  ~180-204) drops a leading `.expressionStatement(.literal("times"))` from a
  `.repeatCount` body before the allowlist walk; called once, at the
  `.repeatCount` case (~line 233). Its own doc says it is purely a
  validation-time tolerance and the returned AST is untouched (so both
  surfaces execute the artifact) — meaning removing the artifact at the
  parser preserves cross-surface equivalence by construction.
- The validator uses a token-segment **line cursor** to name the first
  offending line in E9. The artifact statement "does not own a segment" and
  "shares the same source line as the header" — so removing it must NOT
  desync the cursor (the header is still one segment; body statements own
  their own).

## Decision

1. **Parser**: in the bare-count branch, after `let count = try
   parseExpression()`, consume an optional `times` keyword before
   `skipNewlines()`:
   ```swift
   let count = try parseExpression()
   if current.type == .times { _ = advance() } // `repeat N times`
   skipNewlines()
   let body = try parseRepeatBody()
   ```
   `times` stays OPTIONAL (classic HyperTalk also accepts bare `repeat N`),
   so `if current.type == .times` (not `expect`). `parseExpression` stops at
   `.times` (not a binary operator), so `current` is `.times` here.
2. **Validator**: delete `strippingTimesArtifact` (function + doc comment)
   and change the `.repeatCount` body validation from
   `refusal(forStatements: strippingTimesArtifact(body), …)` to
   `refusal(forStatements: body, …)`. With the artifact gone from the parse,
   the body's first real statement is the first thing to validate, and the
   line cursor advances over the header segment (which still contains the
   `times` token) exactly as before — so E9 line numbers are unchanged.

## Risks / Trade-offs

- **Line-cursor desync (the one real risk).** The cursor is driven by token
  segments (runs between `.newline` tokens), not the AST. Consuming `.times`
  leaves it in the header segment (same line as before), so the segment
  structure is identical; only the AST loses a no-op statement. The turtle
  E9 line-number tests + cross-surface equivalence assert this. If a test
  fails, the cursor's per-statement advance for the `.repeatCount` body was
  (incorrectly) relying on the artifact occupying an advance — fix by
  removing that reliance, not by re-adding the artifact.
- **`repeat N` / `repeat for N times` / nested `repeat N times`.** All still
  parse: `times` optional; `for` still consumed first; nested loops recurse
  through the same branch.
- No document-format, capability, or vocabulary change. The
  `turtle-publish-gating` `.expressionStatement(.literal)` gate is unaffected
  and remains correct (just no longer reached via `repeat N times`).

## Test plan

- `Tests/HypeCoreTests/RepeatTimesParsingTests.swift` (new): parse
  `repeat 3 times / forward 10 / end repeat` and assert the `.repeatCount`
  body has exactly ONE statement (the `forward`), not two; `repeat 3 / … `
  (no `times`) and `repeat for 3 times / …` also parse to a clean single-
  statement body; a nested `repeat 2 times` body is clean too.
- The whole suite stays green — especially `TurtleCrossSurfaceEquivalenceTests`
  (E9 line numbers, garden equivalence), `TurtleScriptingTests`,
  `InterpreterFuzzTests` (turtle grammar + metamorphic, which exercise
  `repeat N times`), and every `repeat N times` interpreter test (counts run
  N times).

## Conditions for Builder

1. **Consume `times` optionally, matching lexer + other forms.** Use
   `if current.type == .times { _ = advance() }` after the count expression,
   before `skipNewlines()`. Do not make it mandatory (`repeat N` stays
   valid). Do not alter `repeat with`/`repeat while`/`repeat`/`repeat for`.
2. **Remove the validator workaround fully.** Delete `strippingTimesArtifact`
   and pass `body` directly at the `.repeatCount` case; no other validator
   logic changes.
3. **Behavior + line-cursor preserved.** `repeat N times` still runs N
   times; E9 line numbers and cross-surface equivalence unchanged. The whole
   test suite stays green; add the parser-cleanliness test.
4. **Don't touch** the `turtle-publish-gating` `.expressionStatement(.literal)`
   gate (it stays, correct and harmless).
