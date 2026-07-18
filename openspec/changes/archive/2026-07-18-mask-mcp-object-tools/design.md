# Design — mask-mcp-object-tools

## Context

HypeDebugServer (local Unix socket in a 0700 directory, auto-started at every app launch — HypeApp.swift:148) carries the MCP surface used by external AI automation. The curated AI/HypeTalk read surfaces mask secure-field text as `(masked)` when `part.partType == .field && part.fieldStyle == .secure`:

- `HypeToolExecutor.swift:3778-3783` — `get_part_property` text/textcontent
- `HypeToolExecutor.swift:6277-6283` — `formatAllProperties` (describe/introspection dump)
- `HypeToolExecutor.swift:760` — part listing (`text=(masked)`)
- `Interpreter.swift:5768-5773` — HypeTalk `the text of field …`

The MCP object tools bypass all of this by serializing whole Codable values through `codableJSONValue` (`HypeMCPDocumentBackend.swift:679-685`).

### Exhaustive enumeration of serialization sites (HypeMCPDocumentBackend.swift)

All `codableJSONValue` / `JSONEncoder` call sites in the MCP directory were enumerated; there are no others.

| Line | Path | Serializes | Secure text? | Action |
|---|---|---|---|---|
| 90 | readResource `…/stack/full` | Stack | no — Stack.swift has no Part/text fields | none |
| 109 | readResource `…/part/{id}/full` | Part | **YES** | mask |
| 119 | readResource `…/card/{id}/full` | Card | no — Card.swift:5-16; parts live only at `HypeDocument.parts` (HypeDocument.swift:11) | none |
| 125 | readResource `…/background/{id}/full` | Background | no — Background.swift:5-14 | none |
| 489 | `fullDocumentResource()` — serves both the `/document` resource (L86-88) and `hype_get_stack_document` (L198-199) | HypeDocument (embeds `parts`) | **YES** | mask |
| 506 | `getObject` stack | Stack | no | none |
| 509 | `getObject` card | Card | no | none |
| 512 | `getObject` background | Background | no | none |
| 515 | `getObject` part — also reached via `hype_open_script_editor` (L207) | Part | **YES** | mask |
| 558/562/566 | `setScript` stack/card/background echo | Stack/Card/Background | no | none |
| 570 | `setScript` part echo | Part | **YES** | mask |
| 600 | `replacePart` echo | Part | **YES** | mask |
| 619 | `decodePart` input encoding | (input, not output) | n/a | none |

Summary emitters (`partSummary` L466-484, `cardSummary` L420-430, `backgroundSummary` L432-441, `stackSummary` L393-418, `appState` L373-391, `transactionSummary` L687-709) contain no `textContent`. Transaction operation `result` strings come from curated executor tools, which already mask. `HypeMCPPreferenceStore` already redacts provider secrets.

## Decision 1 — Masked copy of the value type (not serialization-time filtering)

Add to `HypeMCPDocumentBackend` (all `private`; masking is a transport concern of the MCP boundary, so it lives at the boundary, never in the model):

```swift
private static let secureFieldMask = "(masked)"

/// Copy of `part` safe for MCP transport: every MASKED field-body
/// text property replaced by the sentinel. Predicate mirrors
/// HypeToolExecutor.swift:3778-3783 exactly.
private func maskedForTransport(_ part: Part) -> Part

/// Copy of `document` with every part masked for transport.
private func maskedForTransport(_ document: HypeDocument) -> HypeDocument
```

Semantics: if `part.partType == .field && part.fieldStyle == .secure`, the copy's `textContent`, `htmlContent`, AND `searchText` all become `Self.secureFieldMask` — unconditional (even when empty), matching the curated one-liners; no other property is altered. Document version: copy with `parts = parts.map(maskedForTransport)`.

**Why `htmlContent` and `searchText` too (Security (plan) re-reviews, Findings 1-2):** `Part.htmlContent` (Part.swift:85) and `Part.searchText` (Part.swift:388) are each independently-settable plain `String` properties with no `fieldStyle` guard on any setter and no sync to `textContent`, serialized verbatim by the synthesized Codable encoder at every one of the five part-bearing sites. A client can `set_part_property htmlcontent` (or `searchtext`) `"<secret>"` on a secure field and read the secret back plaintext through any object path — the same exploit shape as `textContent`, three times over. Both are masked here symmetrically with `textContent`. (The curated getters for these two still return plaintext — `htmlContent` via its property cases, `searchText` at HypeToolExecutor.swift:3988 and Interpreter.swift:5805 — and are hardened in the sibling `control-property-consistency` change; out of this change's file whitelist.)

### Durable completeness rule — field-body text (structure over vigilance)

Two consecutive plan reviews each found one more hand-missed property; an enumerated list decays. The masked set is therefore *defined by a rule* and *enforced by a structural test* (Testing notes, tests S1-S2), so completeness rests on Swift's own property list, not on a reviewer re-reading Part.swift.

**Rule.** A `Part` `String` stored property is **field-body text** — and MUST be masked for a secure field — iff both hold:

1. it is settable through any mutation surface with **no `fieldStyle` guard**, and
2. it can **plausibly hold the field's real typed value**: it stores content *bound to the field's value*, not chrome the UI already renders in cleartext while the field obscures its value. Placeholders, prompts, titles, tooltips, and labels are chrome — a secret placed there self-displays on screen, so masking it buys no confidentiality and costs round-trip fidelity.

**Application (current `Part`):** MASKED = { `textContent` (Part.swift:45), `htmlContent` (:85), `searchText` (:388 — a value binding, "currently bound search text", returned plaintext by curated getters with no style or type guard) }. Every other `String` stored property is EXEMPT under clause 2 — e.g. `searchPrompt` (:391) and `helpText` (:64) are author-set chrome rendered in cleartext (`searchPrompt` displays whenever the field is empty; defense-in-depth masking was considered and declined — zero confidentiality gain, real fidelity cost, ruling recorded here for the audit trail); `script` (:440) is exposed by design via the script tools; `name`, `menuTitle`, `dividerColor`, the gauge/music/map/etc. strings are config. Nested Codable stored types were audited and hold no field-bindable text: `PathPoint` is x/y Doubles (HypeStack.swift:135-139); `AssetRef` is asset name/mimeType metadata (AssetRef.swift:4-16). A future nested type that gains user-text storage enters this rule's scope.

**Extension protocol.** Any new `String` stored property added to `Part` must be classified MASKED or EXEMPT under the rule; structural test S1 fails until it is. The MASKED/EXEMPT constants in `MCPMaskingTests.swift` are the single audit point — future reviewers extend by the rule, not by memory.

Why copy, not serialization-time filtering: the copy is compiler-checked against the real `Part` shape (a JSON-tree key walk silently misses renames or nesting); it requires zero model/Codable changes; a value-type copy is negligible next to the JSON encode it feeds; and it is trivially idempotent.

Application — wrap exactly the five part-bearing sites:

- L109 → `codableJSONValue(maskedForTransport(part))`
- L489 → `codableJSONValue(maskedForTransport(document))`
- L515 → `codableJSONValue(maskedForTransport(part))`
- L570 → `codableJSONValue(maskedForTransport(document.parts[index]))`
- replacePart echo → `codableJSONValue(maskedForTransport(stored))` (Decision 2)

## Decision 2 — Round-trip guard: sentinel-preserve in replacePart

`hype_get_object` → edit → `hype_replace_part` is a legitimate workflow. With GET masked, a naive replace writes the literal `(masked)` over the real secret. Chosen: **preserve**, not reject — rejecting would force clients to obtain plaintext just to move or rename a password field, recreating the exact leak class this change closes.

Exact behavior — inside `replacePart` (`HypeMCPDocumentBackend.swift:576-603`), after the script-validation block (L591-595), replacing the assignment at L597:

```swift
let existing = document.parts[index]
var stored = replacement
var preservedSecureText = false
// Fail-closed guard scope (Security 3rd review, Finding 3): preserve ONLY when the
// replacement KEEPS the part a field (`replacement.partType == .field`). If the same
// replace converts the part away from `.field` (e.g. to a button) while a sentinel is
// present, the sentinel writes through as the literal "(masked)" — the harmless string,
// never the real secret. Rationale: restoring the real secret onto a non-field part would
// (a) render it on-screen (a button draws textContent as its label) and (b) leak it on
// every future read, because maskedForTransport's `.field && .secure` predicate no longer
// matches. Unlike the within-field fieldStyle flip (an accepted declassification reachable
// via curated `set_part_property style`), NO curated tool changes partType, so this path is
// exclusive to replace and must fail closed.
if existing.partType == .field, existing.fieldStyle == .secure, replacement.partType == .field {
    // Independent sentinel checks — a client may edit any subset of the
    // masked field-body properties in one replace; each is preserved on
    // its own sentinel, never coupled to the others.
    if replacement.textContent == Self.secureFieldMask {
        stored.textContent = existing.textContent
        preservedSecureText = true
    }
    if replacement.htmlContent == Self.secureFieldMask {
        stored.htmlContent = existing.htmlContent
        preservedSecureText = true
    }
    if replacement.searchText == Self.secureFieldMask {
        stored.searchText = existing.searchText
        preservedSecureText = true
    }
}
document.parts[index] = stored
```

Response: `"object": codableJSONValue(maskedForTransport(stored))`. When the guard fires (any property preserved), add `"preservedSecureText": .bool(true)` and append ` Preserved stored secure-field text ("(masked)" sentinel detected).` to the result string. When it does not fire, the key is absent and the result string is unchanged. The three sentinel checks are independent (not coupled): a replace that masks only `textContent` must not clobber a real `htmlContent` or `searchText`, and so on for every pairing. The referential-integrity guards (L585-590) and script validation read fields the guard never alters, so their placement and behavior are unchanged.

Ruled cases:

- Existing secure + sentinel → preserve stored text (the round-trip).
- Existing secure + any other text (including empty) → write-through: an intentional new secret value.
- Existing secure + sentinel + `fieldStyle` flipped to non-secure **but still `partType == .field`** → preserve text AND apply the style change; the next GET returns plaintext. This declassification path is already available to any mutating client via curated `set_part_property fieldStyle` followed by `get_part_property text`; accepted under the local-trusted-user profile and disclosed in the tool description.
- **Existing secure + sentinel + `partType` changed away from `.field` (e.g. to `.button`) → guard does NOT fire; the literal `(masked)` writes through (the real secret is NOT restored).** Fail-closed: the converted part shows/serializes the harmless sentinel string, never the secret; a client intentionally converting a secure field to another type must explicitly supply the real text in `part_json`. No curated tool changes `partType`, so this is not the accepted fieldStyle-flip declassification — it must fail closed. Disclosed in the `hype_replace_part` description.
- Existing non-secure part whose `part_json` carries the literal `(masked)` → write-through untouched (GET never masked it, so fidelity is preserved).
- Known limitation: a secure field's actual `textContent`, `htmlContent`, or `searchText` cannot be set to the literal string `(masked)` via `hype_replace_part`; use `set_part_property`. Documented, accepted.
- Sentinel match is exact — case-sensitive, no trimming.

## Decision 3 — replacePart validation ruling

`hype_replace_part` remains an intentionally field-level-unvalidated power tool, now stated in its description. Retained structural guards (unchanged): target id must exist (L582-584); cardId/backgroundId referential integrity (L585-590); script parse validation, default on (L591-595); Codable-level degradations (e.g. unknown `FieldStyle` decodes to `.rectangle`, HypeStack.swift:105-109).

Why not re-run field validations here: (a) the HexColor / strict-SET validators belong to the sibling `control-property-consistency` change and are not merged into this worktree — re-implementing them would fork semantics and guarantee conflicts; (b) as an invariant, field-level value validation is a property-dispatch-surface concern (single-property SET), while replace is the whole-object escape hatch at a local privileged debug boundary operated by a trusted local user; (c) the invariant this change owns is confidentiality, delivered by Decisions 1-2. Follow-up (out of scope, noted for the sibling change's audit trail): once a registry-backed part-level validation entry point exists in main, `replacePart` may adopt it.

## Decision 4 — Description updates (exact strings)

`HypeMCPToolBridge.swift`:

- `hype_get_stack_document` (L95): `Return the full active HypeDocument as JSON, including stack/card/background/part scripts and attributes. Secure (password) field textContent, htmlContent, and searchText are returned as "(masked)". Local privileged MCP/debug boundary only.`
- `hype_get_object` (L100): `Return a full stack, card, background, or part object by UUID or case-insensitive name. Secure (password) field textContent, htmlContent, and searchText are returned as "(masked)".`
- `hype_replace_part` (L172): `Replace one existing Part from full JSON previously read from hype_get_object or hype://stack/{id}/part/{partId}/full. If the stored part is a secure field AND the replacement keeps it a field, any of textContent, htmlContent, or searchText carrying "(masked)" preserves that stored property independently — the secret is not overwritten with the sentinel. If the replacement converts the part to another type (e.g. a button), the "(masked)" sentinel is stored literally, NOT the real secret; supply real text explicitly to convert a secure field's content. Beyond id, card/background reference, and script checks, values are stored as decoded without field-level validation — prefer set_part_property for single-property edits.`

`HypeMCPDocumentBackend.swift` `listResources` (L68), Full Active Stack Document description: `Full HypeDocument JSON, including scripts and all persisted attributes. Secure field textContent, htmlContent, and searchText are masked.`

## Edge cases

- Empty secure field: all three MASKED properties become `(masked)` (matches curated one-liners); the replace round-trip preserves the empty strings.
- `searchText` is masked on secure `.field` parts even though it is primarily the SearchField binding: the property exists — and is settable and readable with no type or style guard — on every part, so on a secure field it is a usable secret store.
- A secret that also appears in another part's non-secure text: masking is per-part, no cross-part scrubbing (matches curated behavior; tests use unique nonces).
- `getObject` aliases `part`/`button`/`field`/`object` (L513) all route through the single masked branch.
- `hype_open_script_editor` inherits masking via `getObject` (L207).
- Masking must never write to `self.document` — copies only.

## Testing notes

New file only: `Tests/HypeCoreTests/MCPMaskingTests.swift` — `import Foundation` / `import Testing` / `@testable import HypeCore`, `@Suite("MCP secure-field masking") @MainActor struct MCPMaskingTests` (file-shape pattern: HypeMCPTests.swift:1-7; secure-part construction pattern: SecurityRegressionTests.swift:14-20). Exercise through the public backend API (`callTool` / `readResource`) — that tests the actual boundary.

Example-test matrix:

1. `hype_get_object` part: secure `textContent`, `htmlContent`, AND `searchText` are all `(masked)`; none of the three plaintext nonces appears anywhere in the serialized response.
2. `hype_get_object` part: rectangle field returns plaintext (all three properties) unchanged.
3. `hype_get_stack_document`: secure part masked (all three properties), non-secure sibling verbatim.
4. `readResource` `hype://stack/{id}/document`: same assertions as 3 (distinct entry point).
5. `readResource` `hype://stack/{id}/part/{partId}/full`: masked.
6. `hype_set_script` on a secure field: echo masked; stored document still holds plaintext and the new script.
7. Round-trip: GET → decode JSON → change geometry → `hype_replace_part` → stored part keeps all three original secrets (textContent, htmlContent, searchText), has new geometry; response `preservedSecureText == true`; echo masked.
7b. Independent-sentinel round-trip (three permutations): a secure part with distinct secrets in all three properties — replace masking exactly ONE property (real new values supplied for the other two) preserves only the masked property and writes the other two through; run once per property. No sentinel may clobber another property's real value.
8. `hype_replace_part` with new plaintext on a secure field: write-through; `preservedSecureText` absent.
9. `hype_replace_part` on a rectangle field with literal `(masked)`: write-through.
10. Secure → non-secure style flip with sentinel, STILL a field: stored text preserved, style changed (pins the accepted within-field declassification ruling).
10b. Secure field → button conversion with sentinel (`partType` field→button, textContent left as "(masked)"): guard does NOT fire; stored part is a button whose `textContent` is the literal `(masked)`, NOT the original secret; a subsequent `hype_get_object` returns `(masked)` and the original secret appears nowhere. Pins the fail-closed partType-change ruling (Security 3rd review, Finding 3).
11. Masking never mutates state: after every read above, `backend.document.parts` still carries plaintext.

Structural tests (enforce the Decision 1 durable rule — these are the completeness gate, not examples):

- **S1 — Classification completeness.** Helper `stringPropertyNames(of part: Part) -> Set<String>` = `Mirror(reflecting: part).children.compactMap { $0.value is String ? $0.label : nil }`. Assert the discovered set equals `MASKED ∪ EXEMPT` exactly, and `MASKED ∩ EXEMPT == ∅`, where `MASKED = ["textContent", "htmlContent", "searchText"]` and `EXEMPT` explicitly lists every other current String property — both as `Set<String>` constants in this test file. Any `String` stored property later added to `Part` fails S1 until classified under the rule. (Soundness: `Part` is a struct of stored `var`s, so Mirror children are the stored properties and reflection over the value type is read-only and Sendable-safe; Part.swift declares no explicit `CodingKeys` enum and no custom `encode(to:)`, so synthesized JSON keys == property names == Mirror labels.)
- **S2 — Structural leak sweep.** (a) Build a secure part (SecurityRegressionTests pattern) and encode it with `JSONEncoder`; deserialize to a mutable `[String: Any]` via `JSONSerialization`. (b) For every name discovered by S1, set `dict[name] = "leak-<name>-<fixedSeedHex>"` — pairwise distinct, none a substring of another; reserialize and decode back to `Part` with `JSONDecoder` (Part's tolerant `init(from:)` accepts every String key; enum-typed keys are untouched, so assert the decoded part still has `partType == .field` and `fieldStyle == .secure`). (c) Ground truth: re-read every String property's post-decode value from the decoded part via Mirror — decode-time sanitizers may alter values; assert each of the three MASKED properties still contains its `leak-` nonce so the sweep can never silently lose its teeth. (d) Install the part in the backend's document (HypeMCPTests setup pattern); for each of `hype_get_object` and `hype_get_stack_document`, flatten the serialized response JSON to one text blob and assert: (i) every MASKED property's post-decode value is ABSENT; (ii) `(masked)` occurs at least 3 times; (iii) every EXEMPT property whose post-decode value still contains its `leak-` marker is PRESENT verbatim — no over-masking, fidelity checked in both directions. Scope: S2 covers Part's top-level `String` stored properties via Swift's own property list — "a human missed a field" becomes "Mirror found a field the code didn't classify"; nested types are ruled out per Decision 1 (PathPoint, AssetRef audit).

Invariants and metamorphic relations (for the Tester's property pass; seeded + reproducible):

- **Leak sweep (multi-part)**: for a generated document (fixed seed, ~32 parts mixing secure/rectangle/transparent/search styles, unique nonce secrets `secret-<i>` set into ALL THREE masked properties — `textContent`, `htmlContent`, `searchText` — on secure parts, so every masking path is exercised), the flattened JSON text of every enumerated read path contains no secure nonce (from any of the three properties) and contains every non-secure text verbatim; `(masked)` occurrence count ≥ 3× secure-part count (all three properties masked per secure part). The invariant asserts no nonce leaks via ANY String property of the masked copy, not only textContent.
- **Idempotence**: masking an already-masked part changes nothing (observable: replace with unedited masked JSON, then GET — stable output).
- **No-op round-trip**: GET part JSON → `hype_replace_part` with the unedited masked JSON → stored part is fully equal to the original, all secrets included.

Existing consumers (enumerated; no updates required, must stay green): `HypeMCPTests.swift:108-133` (full-object resource test uses a button — unaffected), `HypeMCPTests.swift:166-191` (replace test uses a button — unaffected). No other test references these tools.

## Conditions for Builder

1. **Masking semantics identical to curated tools**: mask exactly when `part.partType == .field && part.fieldStyle == .secure`; `textContent`, `htmlContent`, AND `searchText` all become the exact string `(masked)`; unconditional (even when empty); no other Part property altered. The masked set is the Decision 1 rule's MASKED set — change it only by the rule, updating `maskedForTransport`, the Decision 2 guard, and the S1 classification together.
2. **No model/Codable changes**: `Part`, `HypeDocument`, `Card`, `Background`, `Stack` and all Codable conformances untouched; no custom encoders; masking is copy-at-boundary inside `HypeMCPDocumentBackend` only.
3. **Round-trip guard exact behavior**: for an EXISTING stored secure field, independently preserve each of `textContent`, `htmlContent`, and `searchText` when the corresponding replacement property equals `"(masked)"` (each exact, case-sensitive, untrimmed; the three checks must NOT be coupled — a sentinel in any subset must never clobber another property's real supplied value); preservation applies when the replacement changes `fieldStyle` but ONLY while `replacement.partType == .field`; if the replacement changes `partType` away from `.field`, the guard does NOT fire and the literal `(masked)` is stored (fail-closed — the real secret is never restored onto a non-field part); `preservedSecureText: .bool(true)` and the result-string note appear when any property is preserved; all existing structural guards (id, referential integrity, script validation) unchanged.
4. **Complete coverage, nothing extra**: wrap exactly the five part-bearing sites (L109, L489, L515, L570, replacePart echo); the nine non-part sites stay untouched; `maskedForTransport` alters exactly the three MASKED properties — textContent, htmlContent, and searchText — and nothing else. After implementing, grep `codableJSONValue(` and confirm every `Part`/`HypeDocument` argument is wrapped in `maskedForTransport`.
5. **Echoes are responses too**: `hype_replace_part` and `hype_set_script` responses must never carry plaintext secure text even though they are mutation tools.
6. **Stored document integrity**: no masking path may write to `self.document`; pin with test 11.
7. **Tests in the new file only**: all new tests go in `Tests/HypeCoreTests/MCPMaskingTests.swift`; do NOT touch `SecurityRegressionTests.swift` or `ScriptStorageGateIntegrationTests.swift` (both modified concurrently in the main tree) — both must stay green, as must `HypeMCPTests.swift` unmodified.
8. **File whitelist**: no changes outside `Sources/HypeCore/MCP/HypeMCPDocumentBackend.swift`, `Sources/HypeCore/MCP/HypeMCPToolBridge.swift`, and the new test file.
9. **Description strings verbatim**: use the exact strings in Decision 4 for the three tool descriptions and the `/document` resource description.
10. **Verified test run**: run the full HypeCoreTests suite with a real, non-zero test count (note: this machine may need the DEVELOPER_DIR workaround per the toolchain memory).
11. **Structural completeness gate**: implement tests S1 and S2 exactly as specified — Mirror-discovered String property list, explicit MASKED/EXEMPT classification sets, seed-all/assert-absence sweep with post-decode ground truth. Do NOT weaken S2 to an enumerated-nonce sweep; the classification sets in `MCPMaskingTests.swift` are the single audit point for every future String property.
