# Control Property Consistency

## Why

The same part property wears different names on the four author-facing surfaces (Properties Inspector, HypeTalk, AI tools, docs), some properties are reachable on only one surface, and several names silently do the wrong thing: `set the size` writes `textSize`, `set the max of gauge` writes an unused field, and a typo in any SET becomes a silent script variable. The four-surface audit (audit-synthesis.md) confirmed 10 HypeTalk defects (H1–H10), 6 AI-surface defects (A1–A6), 2 inspector rendering bugs plus systematic label drift, and two AI-facing docs that disagree with the dispatch and with each other.

## What Changes

- New `PartPropertyRegistry` in HypeCore — a single immutable declarative table (canonical name, aliases, per-verb applicability, mutability, value kind) that gates and resolves both HypeTalk and AI property dispatch, generates `list_all_properties`, and backs mechanical conformance tests. Hand-written switches keep the write/read semantics (hybrid; see design.md Decision 1).
- **BREAKING**: `set the size of <part>` writes the geometry pair `"width,height"` (was `textSize`); a non-pair value errors with copy naming `textSize`. Applies to HypeTalk and `set_part_property`; AI GET `size` now returns the pair too.
- **BREAKING**: SET of an unknown property on a resolvable object target is a runtime `ScriptError` with a nearest-match hint (was: silent `env.setVariable`). The 11 classic HyperCard no-op stubs plus `scroll` remain declared no-ops. Plain `set <var> to <expr>` is untouched.
- **BREAKING**: type-scoped keys (gauge*/progress*/video*/music*/pdf*/map/calendar/scene3D/field-flag/etc. families) error on SET for a non-applicable partType; polymorphic bare names (`value`, `min`, `max`, `step`, `loop`, `volume`, `autoplay`, `playRate`, `currentTime`, `duration`, `tint`, `prompt`, `total`, `items`, `decimals`, `color`, `contents`, `style`, `background`) dispatch per partType per the normative tables in design.md; unlisted types error.
- Malformed hex written to a color property errors through a shared `HexColor` validator (`""` still clears / means auto). Chart spider validation (`ChartConfig.normalizedHex`) is untouched.
- HypeTalk defect fixes: H1 (shape `style` GET), H4 (`marked` on a part errors), H5 (spaced `user level` stack SET), H8 (`icon` empty sentinel `""`), H9 (background short/long/abbreviated name), plus new read-only `the type of <part>`.
- AI surface: registry gate with the same error copy, one permissive `boolArgument` parser for every boolean write (garbage errors), duplicate dead chart cases deleted (single `applyChartProperty` path), curated gaps closed (video playback family, `popupItems`, field flags, `showsUserLocation`, `invertOnClick`, `animated`, `icon`), `location` unified to HypeTalk geometry/map semantics, and `list_all_properties` generated from the registry (complete, masked, explicit legacy section).
- Inspector: hand-written display names for PartType, ButtonStyle, FieldStyle, ShapeType, SpriteShapeType, ChartType, SceneScaleMode (no `.rawValue` reaches the UI); full label harmonization per design-mock §2 (Contents, Selected Segment, Max, Text Color, Interactive, Style, Source, Display Mode, Apple Music, Artist, Show-X family, Min/Max, node-panel polarity and headers); new rows (shape/image Rotation, button Hilite, video Autoplay/Loop/Volume/Play Rate, map Show User Location, field search Prompt + Search While Typing, sequencer Tracks); `propertyRow` gains `placeholder:`/`unit:`; every hand-rolled section header migrates to `sectionHeading`; accessibility labels on all touched labels-hidden controls.
- Docs: `HypeTalkGuide.swift` property reference regenerated from the registry; `HypeTalk-LLM-Context.md` reconciled as a strict subset; breaking-change notes for `size` and strict-SET in both.

## Capabilities

### New Capabilities

- `part-properties` — unified part-property vocabulary, dispatch, and presentation contract (specs/part-properties/spec.md).

### Modified Capabilities

- none (no existing spec covers this surface; openspec/specs has window-restoration and github-readme only).

## Impact

- `Sources/HypeCore/Script/Interpreter.swift` — GET `partPropertyValue` (~5562–5951), SET `applyPartPropertySet` (~7411–7972) become registry-gated and throwing; three call sites in `executeStatement` (1315, 1595, 1609); stack SET `user level` (1537); background GET branch (5488–5507).
- `Sources/HypeCore/AI/HypeToolExecutor.swift` — `set_part_property` (2054–2447), `get_part_property` (3761–3997), `formatAllProperties` (6235–6465), `boolArgument` unification, chart dead code (2417–2442, 3941–3958).
- New: `Sources/HypeCore/Models/PartPropertyRegistry.swift`, `Sources/HypeCore/Models/PartDisplayNames.swift`, `Sources/HypeCore/Models/HexColor.swift`.
- `Sources/HypeCore/AI/HypeTools.swift` tool descriptions; `Sources/HypeCore/AI/HypeTalkGuide.swift`; `HypeTalk-LLM-Context.md`.
- `Sources/Hype/Views/PropertyInspector.swift` — labels/rows only, no stored-model behavior.
- No stored Codable key changes, no `Part` field renames, no document-version bump. HyperCard importer writes fields directly and is unaffected; classic no-op stubs preserved for imported stacks.
- Tests: new `PartPropertyRegistryConformanceTests`, `PartPropertyDispatchTests`, `PartDisplayNamesTests`, `PropertyInspectorLabelSpecTests`; extensions to `PropertyAuditTests`, `HypeTalkGuideTests`, `InterpreterFuzzTests` (grammar + seeds); benchmark re-run per `docs/HypeTalkBenchmarkBaseline.md`.
