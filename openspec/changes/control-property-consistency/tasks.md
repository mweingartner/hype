<!-- Canonical current checklist. Move superseded plans to history/. -->

## 1. P1 — Registry foundations + HypeTalk dispatch (green build + tests before P2)

- [x] 1.1 Create `Sources/HypeCore/Models/PartPropertyRegistry.swift`: `Descriptor`/`Mutability`/`ValueKind`/`Applicability`/`Resolution`, precomputed lookup, `resolveGet`/`resolveSet`, Levenshtein `nearestName` (distance ≤ 2, candidates filtered by part type), descriptors transcribed 1:1 from the existing switches plus the normative dispatch tables in design.md. Also carries the registry-driven `secureMasked` flag (Security condition 1 sweep: textContent, htmlContent, searchText).
- [x] 1.2 Create `Sources/HypeCore/Models/HexColor.swift` (`normalized(_:) -> String?`: "" passes through, 6/8-digit hex with optional `#` → `#UPPER`, else nil).
- [x] 1.3 Create `Sources/HypeCore/Models/PartDisplayNames.swift` (7 displayName extensions, exhaustive switches per design-mock §2.1/§2.2; SpriteShapeType uses its real cases rect/circle/ellipse/path).
- [x] 1.4 Interpreter SET: `applyPartPropertySet` gains `handler:` param and `throws`; registry gate (unknown/notApplicable/readOnly/noOp) after chart interception; canonical-name switch entry; new/changed cases per design.md (size pair, video family, icon clear, marked error, progress min, color validation); strip shadowing bare aliases from case labels; three call sites (via new `setPartProperty` helper) wrap `PartPropertyError` into `ScriptError` with handler line + objectId.
- [x] 1.5 Interpreter GET: `partPropertyValue` becomes `throws`; registry gate (dispatch-cell errors only; unknown still returns ""); H1 style fix, H4 marked error, H8 icon "", `type` property, videoLoop/videoAutoplay/videoVolume/videoDuration GET cases; four call sites updated. Masking law extended to htmlContent + searchText per Security's amended condition 1.
- [x] 1.6 H5: stack SET `case "userlevel", "user_level"` gains `"user level"` (Interpreter.swift:1537). H9: background GET branch (5488–5507) gains short/long/abbreviated name variants.
- [x] 1.7 Builder inline tests: `Tests/HypeCoreTests/PartPropertyDispatchTests.swift` (dispatch cells, size law, strict-SET, H1/H4/H5/H8/H9, read-only, hex validation, chart parity), `PartPropertyRegistryConformanceTests.swift` (alias uniqueness, round-trip law over registry), `PartDisplayNamesTests.swift`; strict-SET negatives added to `PropertyAuditTests.swift`; registry-driven masking-law suite added to `SecurityRegressionTests.swift` (Security's amended condition 1: textContent/htmlContent/searchText, every alias, both `.secure` and non-secure fields, plus a dedicated `value` bypass test).
- [x] 1.8 Extend `InterpreterFuzzTests.swift`: fixture parts (one per object-ref-reachable major type) + `set/put the <prop> of <target>` generator over canonical/alias/near-miss/bare-polymorphic names; 400 generated cases green, no crash/non-determinism found — `regressionSeeds` stays empty (nothing to pin).
- [x] 1.9 Full filtered suite green with real counts; property-access benchmark before/after recorded in `openspec/changes/control-property-consistency/benchmark-p1.md` (release, 50 iterations, median of 3).

## 2. P2 — AI surface parity (green before P3)

- [x] 2.1 `set_part_property`: registry gate with AI error strings (same copy + did-you-mean), canonical switch entry, boolean kinds through `boolArgument` (nil → error listing tokens), color kinds through `HexColor`, `size` pair case, video playback family, `popupitems`, field flags, `showsuserlocation`, `invertonclick`, `animated`, `icon`; `location` unified to geometry/map semantics; delete dead chart cases 2417–2442 (keep `chartdata`); chart keys error on non-chart parts.
- [x] 2.2 `get_part_property`: extract switch into `static func partPropertyReadValue(_ canonical: String, part: Part) -> String?`; registry gate; `size` returns pair; delete dead chart GET cases 3941–3958 (keep `chartdata`); masking preserved.
- [x] 2.3 Rewrite `formatAllProperties` to iterate registry (applicable + aiExposed), values via `partPropertyReadValue`, alias annotations, defaults column from descriptors, explicit legacy section; masking preserved.
- [x] 2.4 Update `HypeTools.swift` set/get/list tool descriptions (canonical vocabulary, strict errors, breaking notes).
- [x] 2.5 Tests: AI halves of dispatch/round-trip/conformance suites; boolean-parser fuzz over token case/whitespace; `list_all_properties` two-direction diff vs registry; update the four existing list-assertion tests (Phase1ControlsTests, ProgressViewTests, TextStylingTests, HelpTextTests) to the registry output format deliberately. Suite green.

## 3. P3 — Inspector labels and rows (app must build; green before P4)

- [x] 3.1 Adopt display names at PI:74 headline and PI:936 Type row and every enum picker (981, 1009, 1058, 2096, 3625, 4294).
- [x] 3.2 Helper upgrades: `propertyRow(_:binding:placeholder:unit:)`, `numberField(_:binding:unit:)` (tempo idiom trailing unit), accessibility labels wired through.
- [x] 3.3 Apply the §2.3 single-select label table (design.md file plan): common/button/field/shape/webpage/image/video/calendar/pdf/map/colorWell/stepper-slider/segmented/scene3D/audioRecorder/synth/appleMusic/musicQueue/progress/gauge/divider/spriteArea/chart/text-formatting sections, including all new rows (Rotation, Hilite, video playback, Show User Location, Prompt + Search While Typing, Tracks).
- [x] 3.4 Apply §2.4 multi-select and node-panel changes; migrate all hand-rolled headers (2075/2112/2121/2141/2148, 3494/3544/3548/3551/3569/3604/3621/3638/3667/3697/3779, 1287) to `sectionHeading`; flip Hidden→Visible (3294, 3512); physics toggle renames (3795, 3797).
- [x] 3.5 `Tests/HypeCoreTests/PropertyInspectorLabelSpecTests.swift` — source-scan conformance for criteria 13–18 and 20 (no rawValue rendering of the seven enums, exact §2.3 strings, no trailing colons, no parenthesized units, no hand-rolled headers, accessibility-label proximity). Suite green; app target builds.

## 4. P4 — Docs, final conformance, evidence

- [ ] 4.1 Regenerate `HypeTalkGuide` property reference from `PartPropertyRegistry.guideSection` (or hand-reconcile with the conformance test as the enforcer); add breaking-change notes.
- [ ] 4.2 Reconcile `HypeTalk-LLM-Context.md` part-properties list as a strict subset; add breaking-change notes; keep the sync note honest.
- [ ] 4.3 Docs conformance test in `HypeTalkGuideTests.swift` (two-direction walk per spec).
- [ ] 4.4 Full suite green (`scripts/test.sh`), fuzz suite green, benchmark after-numbers recorded alongside baseline; release build size delta noted for the -Osize budget.
