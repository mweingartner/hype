# Part Properties

## ADDED Requirements

### Requirement: One property vocabulary, declared in a registry

HypeCore SHALL declare every scriptable part property exactly once in an immutable, `Sendable` `PartPropertyRegistry`: canonical name, aliases, per-verb applicability (part types, optionally button/field styles), mutability (`getSet`, `readOnly`, `noOpStub`), and value kind. HypeTalk GET/SET dispatch, the AI `get_part_property`/`set_part_property` tools, and `list_all_properties` SHALL resolve property names through this registry. Alias spelling sets SHALL be identical for GET and SET.

#### Scenario: Registry resolves every documented name

- **WHEN** a conformance test resolves every property name and alias listed in `HypeTalkGuide` and `HypeTalk-LLM-Context.md` through the registry
- **THEN** each resolves to a declared property on at least one declared part type, and every non-legacy canonical property appears in the guide

#### Scenario: Alias symmetry

- **WHEN** a test compares the resolvable GET spelling set with the resolvable SET spelling set for every registry property
- **THEN** they are identical, except properties declared read-only, whose SET resolution reports read-only (and never falls through to a variable write)

### Requirement: Polymorphic bare names dispatch by part type

The bare names `value`, `min`, `max`, `step`, `loop`, `volume`, `autoplay`, `playRate`, `currentTime`, `duration`, `tint`, `prompt`, `total`, `items`, `decimals`, `color`, `contents`, `style`, and `background` SHALL resolve per part type to the canonical per-type property according to the normative dispatch tables in design.md (design-mock §3.1/§3.3). On a part type with no declared cell, GET and SET SHALL produce a runtime error naming the property and the part type. Long type-prefixed names SHALL keep working on their own type regardless of the bare-alias tables.

#### Scenario: min/max reach the gauge fields

- **WHEN** a script runs `set the max of gauge "T" to 100`
- **THEN** `the gaugeMax of gauge "T"` returns `100` and `controlMax` is unchanged

#### Scenario: Bare loop routes by media family

- **WHEN** a script sets `the loop of video "Clip"` and `the loop of musicMixer "Mix"` to `true`
- **THEN** `videoLoop` and `musicLoop` are set respectively, and `set the loop of button "OK" to true` errors

#### Scenario: Progress min is fixed at zero

- **WHEN** a script runs `set the min of progressView "P" to 5`
- **THEN** the script errors with copy stating progress always starts at 0 and to set the max instead; `set the min of progressView "P" to 0` completes

### Requirement: size is the geometry pair on both verbs

`the size of <part>` SHALL return `"width,height"` on GET and SHALL accept `"width,height"` on SET, writing part width and height, on both the HypeTalk and AI surfaces. A SET value that does not parse as a two-number pair SHALL error with copy naming `textSize` as the property for text size. `textSize` SHALL be unaffected.

#### Scenario: size round-trips

- **WHEN** a script runs `set the size of button "OK" to "120,48"` then reads `the size of button "OK"`
- **THEN** the read returns `120,48` and the button's width is 120 and height is 48

#### Scenario: Single number errors toward textSize

- **WHEN** a script runs `set the size of button "OK" to 24`
- **THEN** the script errors with `size expects "width,height" — use textSize to set the text size.` and neither geometry nor textSize changes

### Requirement: Unknown-property SET is a strict error

When the SET target resolves to an existing object, an unrecognized property name SHALL produce a runtime error containing the property name and the object's type, with a nearest-match hint (edit distance ≤ 2 against names applicable to that part type) when one exists. No script variable SHALL be created. The classic no-op stubs (`sharedText`, `sharedHilite`, `showLines`, `showPict`, `fixedLineHeight`, `multipleLines`, `dontSearch`, `autoSelect`, `autoTab`, `cantDelete`, `cantModify`, `scroll`/`scrollPos`) SHALL remain accepted no-ops by declaration. `set <var> to <expr>` without an object target SHALL be unchanged.

#### Scenario: Typo errors with a hint

- **WHEN** a script runs `set the gaugvalue of gauge "T" to 5`
- **THEN** the script errors with copy containing `gaugvalue`, the object type, and `did you mean "gaugeValue"?`, and no variable named `gaugvalue` exists afterwards

#### Scenario: Classic stubs still no-op

- **WHEN** an imported classic stack script runs `set the sharedText of field "Notes" to true`
- **THEN** the script completes without error and no field is mutated

### Requirement: Type-scoped keys error on the wrong part type

Setting a type-scoped property (the gauge*, progress*, video*, music*, calendar, pdf*, map, colorWell, scene3D*, sprite-area, segmented, search-field, field-flag, image-flag, icon, and chart key families) on a part type outside its declared applicability SHALL error on both surfaces instead of mutating a never-rendered field. `value`/`on` on a part with no value concept SHALL error on SET. GET of long type-prefixed names remains permissive (reads the stored field).

#### Scenario: gaugeValue on a button

- **WHEN** the AI calls `set_part_property(part_name: "OK", property: "gaugeValue", value: "5")` on a button
- **THEN** the tool returns an error naming `gaugeValue` and `button`, and the part is unchanged

### Requirement: Read-only properties reject writes

`type` (new: returns the partType rawValue), video `duration`, audioRecorder `duration`, `pageCount`, `audioSize`, and the scene3D resolved path SHALL be declared read-only: GET works, SET errors with read-only copy and never writes a variable.

#### Scenario: the type of a part

- **WHEN** a script reads `the type of button "OK"` and then runs `set the type of button "OK" to "field"`
- **THEN** the read returns `button` and the SET errors as read-only

### Requirement: Color writes validate through one hex validator

Every color-kind property write on the HypeTalk and AI surfaces SHALL validate through a shared `HexColor` validator accepting the empty string (clear/auto) and 6- or 8-digit hex with optional leading `#`, storing the normalized uppercase `#`-prefixed form. Malformed values SHALL error. Chart spider color validation via `ChartConfig.normalizedHex` SHALL be unchanged.

#### Scenario: Garbage hex errors

- **WHEN** a script runs `set the fillColor of shape "Box" to "reddish"`
- **THEN** the script errors naming the expected format and the stored fill is unchanged; `set the fillColor of shape "Box" to "#ff0000"` stores `#FF0000`, and setting it to `""` clears to auto

### Requirement: Classic defect fixes hold

Shape `style` GET SHALL return `shapeType` (mirror of SET). `marked` on a part target SHALL error naming it a card property (card target unchanged). The stack SET switch SHALL accept the spaced form `user level`. `the icon of` a button with no icon SHALL return `""` (SET accepts `""` or `"0"` to clear). `background` SHALL support `short/long/abbreviated name` variants like stack/card/part.

#### Scenario: Empty icon is empty

- **WHEN** a script evaluates `the icon of button "Plain" is empty` on a button with no icon
- **THEN** it is `true`

### Requirement: AI surface parity

`set_part_property`/`get_part_property` SHALL resolve names through the registry with the same alias sets and dispatch, parse every boolean write with one permissive parser (true/false, yes/no, y/n, 1/0, on/off, case-insensitive; anything else errors), route all chart keys through `applyChartProperty` only, and expose the previously unreachable curated properties (video playback family, `popupItems`, `dontWrap`, `wideMargins`, `richText`, `enterKeyEnabled`, `showsUserLocation`, `invertOnClick`, `animated`, `icon`). `list_all_properties` SHALL be generated from the registry — no missing, no phantom keys — with secure-field masking preserved and an explicit legacy note for non-scriptable/legacy fields.

#### Scenario: Permissive booleans

- **WHEN** the AI calls `set_part_property(property: "visible", value: "1")`
- **THEN** the part becomes visible; `value: "maybe"` returns an error listing the accepted tokens

#### Scenario: list_all_properties matches the registry

- **WHEN** a test diffs the emitted key set of `list_all_properties` for one part of every part type against the registry's applicable, AI-exposed canonical names
- **THEN** the diff is empty in both directions and a secure field's text renders `(masked)`

### Requirement: Enum display names for every rendered enum

HypeCore SHALL provide hand-written `displayName` mappings (exhaustive switches, no `default`) for PartType, ButtonStyle, FieldStyle, ShapeType, SpriteShapeType, ChartType, and SceneScaleMode per design-mock §2.1/§2.2. No `.rawValue` or `.capitalized` of these enums SHALL reach a rendered inspector string.

#### Scenario: Camel-case types render properly

- **WHEN** the inspector shows a `colorWell`, `scene3D`, or `appleMusicBrowser` part
- **THEN** the headline and Type row read `Color Well`, `3D Scene`, `Apple Music Browser`

### Requirement: Inspector speaks the canonical vocabulary

The Properties Inspector SHALL use the exact labels of design-mock §2.3/§2.4: Title Case, no trailing colons, units as trailing secondary text (never in the label), input-format hints as field placeholders, all section headers through `sectionHeading`, the three empty-state sentinels only, style-scoped conditional rows, and an `accessibilityLabel` equal to the canonical label (plus spelled-out unit) on every labels-hidden control in touched rows.

#### Scenario: Progress speaks Max

- **WHEN** the inspector shows a progressView part
- **THEN** the range row is labeled `Max` (not `Total`) and the caption explains progress runs from 0 to Max

#### Scenario: One polarity for visibility

- **WHEN** the node detail or node multi-select panel shows a hidden node
- **THEN** the toggle is labeled `Visible` (inverted binding), not `Hidden`

### Requirement: Docs agree with dispatch

`HypeTalkGuide` and `HypeTalk-LLM-Context.md` SHALL be regenerated/reconciled from the registry — per property: canonical name, aliases, applicable part types, mutability, value format, sentinels — with the LLM-Context list a strict subset of the guide, and breaking-change notes for `size` and strict-SET in both.

#### Scenario: No phantom documentation

- **WHEN** the docs conformance test walks every property name in both docs
- **THEN** each resolves through the registry, and every non-legacy registry canonical appears in the guide
