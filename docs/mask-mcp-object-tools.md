# Mask MCP Object Tools

## Purpose

The MCP object and document read tools serialized whole `Part`/`HypeDocument` Codable values directly, bypassing the secure-field masking the curated AI/HypeTalk tools already apply. A `.field` part with `fieldStyle == .secure` came back in plaintext through these paths even though `get_part_property`, `formatAllProperties`, part listings, and HypeTalk `the text of field …` all mask it as `(masked)`. This change closes that gap at the MCP transport boundary.

## Value

The plaintext a user types into a secure field — the kind of sensitive input such a field is meant to hide — no longer crosses the MCP transport in cleartext through any object or document read path. HypeDebugServer — a local Unix socket, auto-started at every app launch — is exactly the channel external MCP-connected AI automation uses, so this closes a real disclosure path for that client class. The leak class is closed structurally, not just for today's `Part` shape — a reflection-based test (S1) forces every future `String` stored property added to `Part` to be explicitly classified MASKED or EXEMPT before it can ship, so a new field-body-text property can't silently bypass masking the way `htmlContent` and `searchText` twice did during plan review.

## Scope

**Masked read/echo paths (five):**
- `hype_get_object` (part branch, including its `part`/`button`/`field`/`object` aliases, and the `hype_open_script_editor` request path that reuses it)
- `hype_get_stack_document`
- the `hype://stack/{id}/document` resource
- the `hype://stack/{id}/part/{partId}/full` resource
- the `hype_set_script` part echo
- the `hype_replace_part` echo

**Masked properties (three):** `textContent`, `htmlContent`, `searchText` — every `Part` `String` stored property that is settable through any mutation surface with no `fieldStyle` guard and can plausibly hold the field's real bound value (the "field-body-text rule"). Masking fires whenever `part.partType == .field && part.fieldStyle == .secure`, unconditionally, even on empty properties. Every other `Part` property — chrome like `helpText`/`searchPrompt`, config like `menuTitle`/`dividerColor`, and `script` — is EXEMPT and passes through verbatim.

**Not in scope:**
- The pre-existing NSNumber round-trip bug — tracked separately.
- Field-level value validation for `hype_replace_part` (e.g. HexColor / strict-SET checks) — deferred to the sibling `control-property-consistency` change; `replacePart` keeps only its structural guards (existing id, card/background referential integrity, default-on script parse validation).
- Model/Codable changes of any kind — `Part`, `HypeDocument`, `Card`, `Background`, `Stack` and their Codable conformances are untouched. Masking is copy-at-boundary inside `HypeMCPDocumentBackend` only; the stored document is never mutated by a read.

## Functional details

**Masking (`maskedForTransport`).** Two private helpers on `HypeMCPDocumentBackend` — one for `Part`, one for `HypeDocument` (which maps the part helper over `document.parts`) — return a masked copy of the value for transport. When a part is a secure field, its `textContent`, `htmlContent`, and `searchText` are all replaced with the sentinel `"(masked)"`; no other property changes. The predicate and sentinel are identical to the curated masking already used by `get_part_property`, `formatAllProperties`, and HypeTalk field reads. All five masked sites route their `Part`/`HypeDocument` argument to `codableJSONValue` through this helper.

**Replace round-trip guard (`hype_replace_part`).** Because GET now returns `(masked)` for secure text, a naive GET → edit → REPLACE cycle would overwrite the real secret with the literal sentinel. To prevent that without forcing clients to ever handle plaintext, `replacePart` compares each of the replacement's `textContent`, `htmlContent`, and `searchText` against the stored part's originals:
- The guard only evaluates when the **existing** stored part is a secure field **and** the **replacement** keeps `partType == .field`.
- Each of the three properties is checked independently — a sentinel in one property never affects whether another property's real supplied value is written. A client may edit any subset of the three in a single replace.
- When the replacement's value for a property is exactly `"(masked)"` (case-sensitive, untrimmed), the stored original value for that property is kept instead of being overwritten.
- Any other supplied value (including a changed `fieldStyle`, as long as the part is still a field) writes through as given — this is how the within-field secure→non-secure declassification already reachable via `set_part_property fieldStyle` behaves here too.
- When the replacement changes `partType` away from `.field` (e.g. to `.button`) while a sentinel is present, the guard does **not** fire: the literal string `"(masked)"` is stored, and the original secret is not restored. This is fail-closed by design — restoring a secret onto a non-field part would render it on screen and leak it on every subsequent read, since the masking predicate no longer matches a non-field part.
- On a non-secure stored part, or on any part_json field that isn't a sentinel match, values write through unchanged — masking never affected non-secure GETs, so there's nothing to preserve.
- When any property is preserved, the response includes `"preservedSecureText": true` and the result string gains `" Preserved stored secure-field text (\"(masked)\" sentinel detected)."`. When nothing is preserved, both are absent/unchanged.
- The echoed `object` in the response is always the masked copy of the stored part, whether or not the guard fired — the echo of a mutation is a response too, and never carries plaintext secure text.

**Validation scope (`hype_replace_part`).** Beyond its existing structural guards — the target id must already exist, `cardId`/`backgroundId` referential integrity, and default-on script parse validation — `replacePart` does not gain field-level value validation in this change. It remains an intentionally field-level-unvalidated power tool; the tool description now says so and steers single-property edits to `set_part_property`.

**Structural completeness (tests, not just examples).** `Tests/HypeCoreTests/MCPMaskingTests.swift` discovers every `Part` `String` stored property via `Mirror` and asserts the discovered set exactly equals the union of two explicit constants — `maskedProperties = ["textContent", "htmlContent", "searchText"]` and an `exemptProperties` set listing every other current property (S1). A companion seeded leak sweep (S2) sets a unique nonce into every discovered property of a secure part, reads it back through `hype_get_object` and `hype_get_stack_document`, and asserts no MASKED nonce appears anywhere in the response while every EXEMPT nonce passes through verbatim. Together these mean a new `Part` `String` property that isn't classified fails the suite immediately, rather than silently shipping unmasked.

## Usage

**1. Reading a secure field masks its text.**

```
tool: hype_get_object
args: { "object_type": "part", "id_or_name": "password" }
```
If `password` is a `.field` part with `fieldStyle: secure`, the response's `object.textContent`, `object.htmlContent`, and `object.searchText` are all `"(masked)"` — the real stored values never appear in the response, and the backend's stored document is untouched (still holds the plaintext).

**2. Safe GET → edit → REPLACE preserves the secret.**

```
tool: hype_get_object
args: { "object_type": "part", "id_or_name": "password" }
# → object.textContent == "(masked)", object.htmlContent == "(masked)", object.searchText == "(masked)"

# client edits only geometry (e.g. width/height) in the returned JSON, leaving
# textContent/htmlContent/searchText as the "(masked)" sentinel it received

tool: hype_replace_part
args: { "part_json": "<edited JSON with new geometry, sentinel text/html/search fields, partType still \"field\">" }
```
The stored part keeps its original secret `textContent`, `htmlContent`, and `searchText` and gains the new geometry. The response includes `"preservedSecureText": true`, and the echoed `object` is masked.

**3. Converting a secure field to another type does not resurrect the secret.**

```
tool: hype_get_object
args: { "object_type": "part", "id_or_name": "password" }
# → textContent == "(masked)"

tool: hype_replace_part
args: { "part_json": "<same JSON, but \"partType\" changed to \"button\", textContent left as \"(masked)\">" }
```
Because the replacement no longer keeps `partType == .field`, the guard does not fire: the stored button's `textContent` becomes the literal string `"(masked)"`, not the original secret, and `preservedSecureText` is absent. To convert a secure field's content to a different part type, supply the real text explicitly in `part_json` instead of leaving the sentinel in place.
