# repeat N times: consume the trailing `times` token

## Why

`Parser.parseRepeatStatement`'s bare-count branch parses the count
expression then `skipNewlines()` — it never consumes the `times` keyword
sitting between them (`times` lexes to a `.times` token; only the other
repeat forms consume their own trailing keywords). So `parseRepeatBody`
reads the leftover `times` as the loop's FIRST body statement: every
`repeat N times` loop's AST body begins with a stray
`expressionStatement(.literal("times"))`. It runs as a harmless no-op, but
it is a latent defect with two shipped costs:

1. It made every `repeat N times` loop publish once per iteration (a
   full-card redraw), until the `turtle-publish-gating` change mitigated the
   symptom by gating bare-literal expression statements out of the publish
   decision. The stray statement still exists and still executes.
2. `TurtleProgramValidator` carries a `strippingTimesArtifact` workaround
   solely to skip this stray statement during its allowlist walk.

## What Changes

- In `parseRepeatStatement`'s bare-count branch, consume an optional
  trailing `times` token (`.times`) after the count expression, before
  `parseRepeatBody` — matching how `repeat with … to …` / `repeat while`
  consume their own keywords. `repeat N times` bodies are now clean.
- Remove `TurtleProgramValidator.strippingTimesArtifact` and its call site
  (the `.repeatCount` body now validates directly) — the artifact it worked
  around no longer exists. Cross-surface equivalence still holds (both the
  HypeTalk surface and the tool parse identical, artifact-free ASTs).
- The `turtle-publish-gating` change's `.expressionStatement(.literal)`
  publish gate stays (a bare literal statement is still a no-op if one ever
  appears); it is simply no longer exercised by `repeat N times`.

No behavior change: `repeat N times` still runs the loop N times; the only
difference is the loop body no longer carries a leading no-op.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

_None — a parser defect fix (a dropped token is now consumed) plus removal
of the validator workaround it necessitated._

## Impact

- `Sources/HypeCore/Script/Parser.swift` — bare-count branch consumes
  `.times`.
- `Sources/HypeCore/Script/TurtleProgramValidator.swift` — remove
  `strippingTimesArtifact` and its use.
- `Tests/HypeCoreTests/RepeatTimesParsingTests.swift` (new) — assert a
  `repeat N times` body has no stray statement, and `repeat N` (no `times`)
  and `repeat for N times` still parse.

Risk: low (local-trusted-user). The one real risk is the validator's
token-segment line cursor desyncing once the artifact statement is gone; the
turtle cross-surface equivalence + E9 line-number tests are the safety net.
