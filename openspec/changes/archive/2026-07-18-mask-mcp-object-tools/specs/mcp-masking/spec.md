# MCP Masking

## ADDED Requirements

### Requirement: Secure-field text never crosses an MCP object or document read path

Every MCP response that serializes a full `Part` or `HypeDocument` SHALL replace the `textContent`, `htmlContent`, AND `searchText` of parts with `partType == .field` and `fieldStyle == .secure` with the exact string `(masked)` before serialization — semantics identical to the curated masking one-liners (`get_part_property`, `formatAllProperties`, HypeTalk GET), including masking empty properties. The masked set SHALL be derived from the field-body-text rule (design, Decision 1): every `String` stored property of `Part` that is settable with no `fieldStyle` guard and can plausibly hold the field's bound value — currently exactly {`textContent`, `htmlContent`, `searchText`}. The covered paths are: `hype_get_object` (part), `hype_get_stack_document`, the `hype://stack/{id}/document` resource, the `hype://stack/{id}/part/{partId}/full` resource, the `hype_set_script` part echo, the `hype_replace_part` echo, and `hype_open_script_editor`'s `requestedObject`. Masking SHALL operate on transport copies only; the stored document is never modified.

#### Scenario: get_object masks a secure field

- **WHEN** `hype_get_object` returns a part with `fieldStyle` secure whose stored `textContent` is `s3cr3t`, stored `htmlContent` is `<b>h1dden</b>`, and stored `searchText` is `f1ndme`
- **THEN** the response object's `textContent`, `htmlContent`, and `searchText` are all `(masked)`, none of `s3cr3t`, `h1dden`, or `f1ndme` appears anywhere in the serialized response, and the backend's stored document still holds all three plaintext values

#### Scenario: stack document masks every secure field

- **WHEN** `hype_get_stack_document` (or the `/document` resource) serializes a document containing secure and non-secure fields
- **THEN** every secure part's `textContent`, `htmlContent`, and `searchText` read `(masked)` and every non-secure part's text properties are returned verbatim

#### Scenario: non-secure fields unaffected

- **WHEN** `hype_get_object` returns a rectangle-style field with `textContent` `hello world`
- **THEN** the response carries `hello world` unchanged

### Requirement: Masking completeness is enforced structurally

The masking test suite SHALL discover every `String` stored property of `Part` from the type itself (reflection over Swift's own property list, not a hand-maintained inventory) and SHALL require each discovered property to be classified as MASKED (field-body text) or EXEMPT (chrome/config/code) under the field-body-text rule. A leak sweep SHALL seed a unique nonce into every discovered `String` property of a secure part and assert that no MASKED property's value survives in any covered response while EXEMPT properties pass through verbatim.

#### Scenario: a new String property cannot bypass classification

- **WHEN** a `String` stored property is added to `Part` without being classified MASKED or EXEMPT
- **THEN** the structural classification test fails until the property is classified under the field-body-text rule

#### Scenario: seeded nonces never leak through masked properties

- **WHEN** every `String` stored property of a secure part is seeded with a unique nonce and the part is read via `hype_get_object` or `hype_get_stack_document`
- **THEN** no nonce seeded into a MASKED property appears anywhere in the response, and nonces in EXEMPT properties are returned verbatim

### Requirement: Replace round-trip preserves the stored secret

When `hype_replace_part` targets a stored part that is a secure field AND the replacement keeps `partType == .field`, the tool SHALL independently preserve each of the stored `textContent`, `htmlContent`, and `searchText` when the corresponding supplied property in `part_json` is exactly `(masked)`. The three sentinel checks SHALL NOT be coupled: a sentinel in any subset of the properties must never clobber another property's real supplied value. When any property is preserved the tool SHALL report `preservedSecureText: true` and echo the stored part masked, writing all other supplied fields (including a changed `fieldStyle`, as long as the part stays a field). If the replacement changes `partType` away from `.field`, the tool SHALL NOT preserve — the literal string `(masked)` SHALL be stored, so the real secret is never restored onto a non-field part (fail-closed). Any other supplied value for these properties on a secure field SHALL be written as given. On a non-secure stored part the literal string `(masked)` SHALL be written verbatim. Sentinel comparison SHALL be exact — case-sensitive, untrimmed.

#### Scenario: GET then edit then REPLACE keeps the secret

- **WHEN** a client reads a secure field via `hype_get_object`, changes only geometry in the returned JSON, and calls `hype_replace_part`
- **THEN** the stored part has the new geometry and the original secret `textContent`, `htmlContent`, and `searchText`, and the response contains `preservedSecureText: true` with a masked echo

#### Scenario: sentinel in one property does not clobber the others

- **WHEN** `part_json` for a secure field carries `(masked)` as `textContent`, a new plaintext `htmlContent`, and a new plaintext `searchText`
- **THEN** the stored `textContent` is preserved and the supplied `htmlContent` and `searchText` are written through

#### Scenario: explicit new secret writes through

- **WHEN** `part_json` for a secure field carries `textContent` `newSecret`
- **THEN** the stored `textContent` becomes `newSecret` and `preservedSecureText` is absent from the response

#### Scenario: literal sentinel on a plain field writes through

- **WHEN** `part_json` for a rectangle-style field carries `textContent` `(masked)`
- **THEN** the stored `textContent` is the literal `(masked)`

#### Scenario: converting a secure field to another type does not restore the secret

- **WHEN** a client reads a secure field via `hype_get_object` and calls `hype_replace_part` with `partType` changed to `button`, leaving `textContent` as the `(masked)` sentinel
- **THEN** the stored part is a button whose `textContent` is the literal `(masked)`, the original secret is not restored and appears nowhere in the stored document or any subsequent read, and `preservedSecureText` is absent from the response

### Requirement: replacePart validation scope is explicit

`hype_replace_part` SHALL keep its structural guards (existing id, card/background referential integrity, default-on script validation) and SHALL NOT gain field-level value validation in this change; its tool description SHALL state the sentinel-preserve behavior and the absence of field-level validation, steering single-property edits to `set_part_property`.

#### Scenario: descriptions disclose the contract

- **WHEN** a client lists MCP tools
- **THEN** the `hype_get_object` and `hype_get_stack_document` descriptions state that secure `textContent`, `htmlContent`, and `searchText` are returned as `(masked)`, and the `hype_replace_part` description states the per-property sentinel-preserve rule and that values beyond the structural checks are stored as decoded
