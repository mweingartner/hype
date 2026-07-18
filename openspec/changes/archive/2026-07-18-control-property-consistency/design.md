# Design: Control Property Consistency

## Context

Design-mock.md (decisive on vocabulary) and audit-synthesis.md (file:line evidence) define the change: one property vocabulary spoken identically by the Properties Inspector, HypeTalk, the AI tools, and the docs. Hard constraint: no stored `Part` field renames, no Codable key changes, no document-version bump. The dispatch reality today: HypeTalk GET (`partPropertyValue`, Interpreter.swift:5562–5951, unknown → `""` at 5949), HypeTalk SET (`applyPartPropertySet`, 7411–7972, unknown → `env.setVariable` at 7969–7971), AI SET (HypeToolExecutor.swift:2054–2447, unknown → error at 2443), AI GET (3761–3997, unknown → error at 3995), `formatAllProperties` (6235–6465, hand-maintained and incomplete). Verified: no existing test depends on `size`→textSize SET, variable fallthrough, controlMin/Max via bare names on non-form controls, part-`marked`, or icon `"0"`; `AudioKitMusicTests` pins bare `volume` on music parts (kept by the dispatch tables); `Phase5VideoTransportTests` pins `duration` on video and audioRecorder (kept); the HyperCard importer writes Part fields directly and never enters this dispatch; the fuzzer does not currently generate property statements.

## Goals / Non-Goals

**Goals**: registry as single source of truth; the design mock's 21 acceptance criteria mechanically testable; H1–H10 and A1–A6 fixed; inspector label spec §2/§2.4 realized; docs conformant; fuzz suite extended; hot-path performance held (property-access benchmark within noise).

**Non-Goals**: model renames / Codable migration (audit R7 — explicitly out); MCP `hype_get_object`/`hype_replace_part` masking policy (Security phase owns, deferral §7.4); registry-driven runtime replacement of the semantic switches; changing the not-found-target fallback (Interpreter.swift:1603–1605) — documented residual, recommended follow-up; GET of a fully unknown name still returns `""` (mock strictens SET only — documented decision); node-layer (`applyNodePropertySet`) naming; icon picker UI, track editor, `pdfAssetRef` tool (mock §7 deferrals).

## Decision 1 — Hybrid registry: registry gates and resolves; switches implement

`PartPropertyRegistry` **describes** every property and **drives** name resolution, applicability/mutability gating, `list_all_properties`, docs generation, and the conformance tests — while the hand-written GET/SET switches keep the semantics, now keyed by the canonical name the registry resolves to.

Rejected — full registry-driven dispatch (descriptors carry getter/setter closures): the SET switch embeds at least seven non-trivial behaviors (script-gate + sprite-scene routing, GIFAnimator main-thread hop, menuItems inline-script parse validation, Scene3D binding resolver capturing a context-dependent path resolver, musicSource decode, map location heuristics, card-`marked` mutation). Closure-izing them means capturing `env`/`document`/`context` in `@Sendable` closures — fighting Swift 6 strict concurrency — and produces a ~1,500-line unreviewable diff on the interpreter hot path in one pass. Rejected — registry as test-only description: leaves the strict-SET gate, type-scoping, and alias collapse hand-written in three places; drift returns the day the tests are relaxed.

The hybrid: resolution runs once per property access — one precomputed `Dictionary` lookup on the already-lowercased name (no new allocation; pass the lowered string into the switch). `.unknown`→error(+Levenshtein hint, error path only), `.notApplicable`→error, `.readOnly`→error (SET), `.noOp`→return, `.property(canonical)`→existing switch keyed on canonical. Polymorphic bare names resolve to per-type canonicals (e.g. `min`@gauge → `gaugemin`), so H3 dies without new switch cases; only genuinely new behavior (size pair, video family, icon clear, progress-min) adds cases. Registry is `static let`, all-value-type, `Sendable`, no closures, no locks — strict-concurrency clean and -Osize friendly (pure data; offset by ~50 deleted dead chart lines).

Sketch (signatures only):

```swift
public enum PartPropertyRegistry {
    public struct Applicability: Sendable {
        public let types: Set<PartType>?          // nil = universal
        public let buttonStyles: Set<ButtonStyle>? // extra constraint when .button
        public let fieldStyles: Set<FieldStyle>?   // extra constraint when .field
    }
    public enum Mutability: Sendable { case getSet, readOnly, noOpStub }
    public enum ValueKind: Sendable { case string, number, boolean, color, pair, enumeration, json }
    public struct Descriptor: Sendable {
        public let canonical: String        // lowercase key the switches use
        public let aliases: [String]        // lowercase; GET set == SET set by construction
        public let getApplicability: Applicability
        public let setApplicability: Applicability
        public let mutability: Mutability
        public let kind: ValueKind
        public let aiExposed: Bool          // false: HypeTalk-only legacy (htmlContent, menu*)
        public let legacy: Bool             // listed under the legacy note in list_all_properties
        public let defaultDescription: String
        public let docSummary: String
    }
    public enum Resolution: Sendable, Equatable {
        case property(canonical: String)
        case noOp
        case readOnly(canonical: String)
        case notApplicable(name: String, appliesTo: String)
        case unknown(suggestion: String?)
    }
    public static let descriptors: [Descriptor]
    public static func resolveGet(_ loweredName: String, for part: Part) -> Resolution
    public static func resolveSet(_ loweredName: String, for part: Part) -> Resolution
    public static func nearestName(to loweredName: String, for type: PartType) -> String? // Levenshtein ≤ 2
    public static func guideSection() -> String       // docs generation
    public static func allPropertiesReport(for part: Part, value: (String) -> String?) -> String // list_all_properties body
}
struct PartPropertyError: Error, Sendable, LocalizedError { let message: String; var errorDescription: String? { message } }
```

Descriptor population: transcribe the existing case labels 1:1 (mechanical; conformance tests enforce agreement), then apply the normative tables below.

## Decision 2 — Error propagation

`applyPartPropertySet` gains `handler: Handler` and `throws`; it throws `PartPropertyError`; the three call sites (Interpreter.swift:1315 put-into-property, 1595 set-of-objectRef, 1609 set-of-me) wrap into `ScriptError(message:, line: handler.line, handler: handler.name, objectId: part.id)`. `partPropertyValue` becomes `throws` (four call sites: 5299, 5513, 5524, 5551) and throws `PartPropertyError`; the top-level catch (Interpreter.swift:731–733) already wraps arbitrary errors into `ScriptError` via `localizedDescription`, which `PartPropertyError` satisfies through `LocalizedError`. GET errors therefore carry the message verbatim with handler-level line info — acceptable, and no threading of `handler` through `evaluate`.

## Decision 3 — GET leniency scope

SET is strict (mock §3.7). GET errors only where the dispatch tables declare an error cell (bare polymorphic names on unlisted types) and for `marked` on a part. GET of long type-prefixed names stays universal-read (harmless stored-field read; protects speculative reads in existing stacks); GET of a fully unknown name keeps returning `""` (changing it is not in the mock and would destabilize `the <anything> of` patterns; flagged for the Designer at Review as a documented decision).

## Decision 4 — Hex validation

New `HexColor.normalized(_ raw: String) -> String?` in `Sources/HypeCore/Models/HexColor.swift`: `""` → `""` (clear/auto); 6- or 8-digit hex, optional `#`, case-insensitive → `#UPPERCASE`; else nil → error. Grammar is the union of what the renderers accept (`NSColor(hexString:)` 6-digit, ShapeRenderer.swift:119; `GlassRenderer.nsColorFromHexWithAlpha` 6/8-digit, GlassRenderer.swift:191; `ColorRef.normalizedHex` 6/8, ColorRef.swift:98) so no currently-renderable value becomes an error; named colors were never rendered and now error instead of silently falling back. Stored form is normalized (uppercase, `#`), making round-trips stable. Applies to color-kind part properties on both script surfaces. `ChartConfig.normalizedHex` (ChartModel.swift:357–364) and all chart paths are untouched.

## Decision 5 — Display names live in HypeCore

`Sources/HypeCore/Models/PartDisplayNames.swift`: `displayName` extensions for `PartType` (mock §2.1 table verbatim), `ButtonStyle`, `FieldStyle`, `ShapeType`, `SpriteShapeType`, `ChartType`, `SceneScaleMode` (mock §2.2) — exhaustive switches, no `default`, so new cases fail compilation. HypeCore placement lets PropertyInspector, exporters, and future surfaces share them. **Design-mock erratum flagged for Review**: SpriteShapeType's real cases are `rect, circle, ellipse, path` (SceneSpec.swift:605), not the ShapeType list §2.2 implies — proposed: Rectangle, Circle, Ellipse, Path.

## Decision 6 — Docs generation

`HypeTalkGuide.llmContext` (HypeTalkGuide.swift:45) interpolates `PartPropertyRegistry.guideSection()` for the part-property reference (line 170 region) instead of the hand-written list; `HypeTalk-LLM-Context.md` line 98 list is hand-reconciled as a strict subset. The two-direction conformance test (extend `Tests/HypeCoreTests/HypeTalkGuideTests.swift`) is the enforcement: every doc property name resolves through the registry; every non-legacy canonical appears in the guide; the .md file is located via `#filePath`-relative navigation.

## Decision 7 — Where inspector conformance tests live

`HypeTests` (AppKit) is excluded from headless runs (AGENTS.md), so label conformance lives in `Tests/HypeCoreTests/PropertyInspectorLabelSpecTests.swift` as source-scan assertions over `Sources/Hype/Views/PropertyInspector.swift` (read via `#filePath`): exact §2.3 strings present, banned patterns absent (`.rawValue` rendering of the seven enums, trailing-colon labels, parenthesized units, hand-rolled header literals), accessibility-label proximity to `labelsHidden()`. Render-level verification (criterion 19/21) is the Designer's Sign-off checklist — states this explicitly rather than pretending headless coverage.

## Normative dispatch tables (registry data)

Bare-name → per-type canonical; **any type not listed in a row errors on both verbs** (except as noted). Long prefixed names always work on their own type.

| Bare name | Dispatch |
|---|---|
| `value` | SET: stepper/slider→controlValue, gauge→`setGaugeValue`, progressView→`setProgressValue`, toggle→bool, segmented→index, field→textContent; others **error** (A2). GET: same cells; **others keep existing controlValue read** (mock §3.1 "existing behavior") |
| `on` | toggle only (bool); others error |
| `min` | stepper/slider→`min`(controlMin), gauge→`gaugemin`, calendar→`mindate`, progressView→GET `"0"`, SET only 0 accepted else error `progress always starts at 0 — set the max instead.` |
| `max` | stepper/slider→`max`(controlMax), gauge→`gaugemax`, calendar→`maxdate`, progressView→`progresstotal` |
| `step` | stepper/slider→`step`(controlStep) only |
| `loop`/`looping` | video→`videoloop` (new cases), music family (musicPlayer, pianoKeyboard, stepSequencer, musicMixer, appleMusicBrowser, musicQueue)→`musicloop` |
| `volume` | video→`videovolume` (new), music family→`musicvolume` |
| `autoplay` | video→`videoautoplay` (new) |
| `playrate`/`rate` | video→`videoplayrate` (restrict: today universal) |
| `currenttime` | video→`videocurrenttime` (restrict) |
| `duration` | video→`videoduration` **read-only**; music family→`musicduration` (get+set as today); audioRecorder→`audioduration` **read-only** |
| `tint` | gauge→`gaugetint`, progressView→`progresstint` (fixes HypeTalk SET tint→gauge-always at 7880 and AI tint→progress-always at 2304/3967) |
| `prompt` | field(style .search) + legacy searchField→`searchprompt` |
| `total` | progressView→`progresstotal` (compat alias of `max`) |
| `items` | button→`popupitems`, menu→`menuitems` |
| `decimals` | gauge→`gaugedecimals`, progressView→`progressdecimals` (was silent "0"/no-op elsewhere) |
| `style` | button→`buttonstyle`, field→`fieldstyle`, shape→`shapetype` (H1: GET now mirrors SET; `shape`/`shapetype` aliases stay) |
| `color` | colorWell→`colorwellhex`, divider→`dividercolor` (fixes bare color→colorWellHex on every type) |
| `contents` | field→`textcontent` (classic; §1.3) |
| `background` | scene3D→`background3d` (short form; `scenebackground` alias stays) |
| `size` | universal, own canonical: GET `"w,h"` (unchanged), SET parses pair→width/height; non-pair errors `size expects "width,height" — use textSize to set the text size.` **Strip `"size"` from the `textsize` case labels on both surfaces** (Interpreter 7441, executor 2392, executor GET 3914) |
| `type` | new universal **read-only**: partType rawValue |

Restricted SET applicability (setTypes; GET stays universal for these long names): gauge* → gauge; progress* → progressView; video*, currenttime, playrate → video; music*, tempo/bpm, instrument, pattern, show* music toggles → music family; keys/keycount → pianoKeyboard; audio recorder family (recording, playing, outputpath, format, saveinstack, audiosize RO) → audioRecorder; calendar fields → calendar; pdf* (+pagecount RO) → pdf; map fields (centerlat/centerlon/span/maptype/annotations/maplocation/showsuserlocation) → map; colorwellhex + interactive → colorWell; scene3D family (object/model/modelurl/modelasset RO-get-alias-now/antialiasing/allowscameracontrol/autolighting/background3d) → scene3D; segments/selectedsegment → segmented; search fields → field+searchField; field flags (locktext/dontwrap/widemargins/richtext/enterkeyenabled) → field; hilite/autohilite/showname → button+toggle; image flags (invertonclick/animated/imagefilter/imagefilterintensity) → image; transparentbackground → image+spriteArea; icon → button; sprite fields → spriteArea; chart keys + chartdata → chart; divider long names → divider; menuitems/menutitle → menu+button; popupitems → button. Universal (unchanged): name/id/geometry/rect/loc/topleft/bottomright/number/owner/visible/enabled/script/helptext/text/textcontent/textfont/textsize/textstyle/textalign/fontcolor family/fillcolor/strokecolor/strokewidth/cornerradius/url/family/animating(RO)/textheight/centered/filled(RO)/linesize.

Alias-symmetry closures (H6): `items` per table; `tint` GET gains the dispatch; `modelasset`/`assetname` become GET aliases on scene3D (read `scene3DAssetRef?.name`, matching AI GET 3904); `contents` added; `total` added to HypeTalk. No-op stubs: the 11 classic field props + scroll/scrollpos → `.noOpStub` (GET keeps hardcoded classic answers, SET returns silently) — exempt from strict-SET **by declaration**.

Error copy (exact): unknown — `no such property "gaugvalue" for button "OK" — did you mean "gaugeValue"?` (hint clause omitted when no candidate ≤ distance 2); wrong type — `"gaugeValue" does not apply to button "OK" — it is a gauge property.`; read-only — `"duration" of video "Clip" is read-only.`; marked — `"marked" is a card property — try the marked of this card.`; color — `"<value>" is not a color — use "#RRGGBB" or "#RRGGBBAA" (empty clears).`; AI boolean — `"<value>" is not a boolean — use true/false, yes/no, on/off, or 1/0.` Suggestions operate on property names only — never echo values (secure-content safety).

## File-by-file change plan

**Create** `Sources/HypeCore/Models/PartPropertyRegistry.swift` (Decision 1 sketch; includes private `levenshtein(_:_:)`), `Sources/HypeCore/Models/HexColor.swift` (Decision 4), `Sources/HypeCore/Models/PartDisplayNames.swift` (Decision 5).

**`Sources/HypeCore/Script/Interpreter.swift`**
- `applyPartPropertySet` (7411): add `handler: Handler`, `throws`; after `setChartLevelProperty` interception insert the resolveSet gate; switch consumes the resolved canonical. New/changed cases: `size` (pair parse; write width/height); `videoloop`/`videoautoplay`/`videovolume` (isTruthy / isTruthy / 0…1 clamp, mirroring musicVolume); `icon` SET accepts `""`/`"0"` → `iconId = nil` (7558); `marked` → throw card-property error (replace 7536–7539); `min` case gains progressView zero-only branch; color-kind writes route through `HexColor` (fillcolor 7443, strokecolor 7445, fontcolor 7495, dividercolor 7944, colorwellhex 7680, gaugetint 7880 — bare `tint` label removed, progresstint 7863, background3d 7831); remove `"size"` from 7441; remove bare `loop`/`looping` from 7750, `volume` from 7752, `tint` from 7880, `prompt` from 7935, `orientation`/`thickness` stay (divider-scoped by registry so labels harmless but strip to be safe); default case becomes `throw` unreachable-conformance error (gate handles unknown). Preserve verbatim: GIF main-thread hop (7593–7623), playRate clamp (7628–7633), menuItems validation+cap (7895–7928), all `prefix()` caps, `setProgressValue`/`setGaugeValue` routing, gaugeMax>gaugeMin (7874–7877), progressTotal floor (7841).
- `partPropertyValue` (5562): `throws`; resolveGet gate after `chartLevelProperty`; H1: `style` case dispatches button/field/shape (5608); H4: `marked` throws (5869); H8: `icon` returns `""` when nil (5883); new `type` case; new GET cases `videoloop`/`videoautoplay`/`videovolume`/`videoduration`; `modelasset`/`assetname` GET alias (scene3DAssetRef name); remove bare polymorphic labels that the registry now dispatches (`loop`/`looping` at 5719, `volume` 5721, `prompt` 5806, `items` 5802, `min/max/step` stay as form-control canonicals). Secure masking at 5768–5773 preserved verbatim. Call sites 5299/5513/5524/5551 add `try`.
- `executeStatement`: 1315/1595/1609 — `try` + wrap `PartPropertyError` → `ScriptError` (line: handler.line, objectId). Leave 1603–1605 (target-not-found fallback) unchanged this change.
- Stack SET 1537: add `"user level"`. Background GET branch 5488–5507: add `short name`/`shortname`/`abbrev…`/`long name`/`longname` variants mirroring the card/part pattern (5577–5583).

**`Sources/HypeCore/AI/HypeToolExecutor.swift`**
- `set_part_property` (2054): after the `.chart`→`applyChartProperty` intercept, resolveSet gate returning the error strings above; boolean-kind values through `boolArgument` (179) with nil→error; color-kind through `HexColor`; new cases: `size` pair, `videoautoplay`/`videoloop`/`videovolume` (+ existing videourl/currenttime/playrate become video-scoped), `popupitems`, `dontwrap`/`widemargins`/`richtext`/`enterkeyenabled`, `showsuserlocation`, `invertonclick` (exists — keep), `animated` (new), `icon`; `location` (2104) unified: coordinate pair→geometry center, non-pair on map→mapLocation, non-map non-pair→error; strip `"size"` from 2392, `"total"` stays as alias (2295), `"tint"` removed from 2304 label (dispatch decides); delete dead chart cases 2417–2442 **except `chartdata`**; chart keys on non-chart parts now error via gate.
- `get_part_property` (3761): extract the switch body into `static func partPropertyReadValue(_ canonical: String, part: Part) -> String?`; the tool resolves via registry then calls it; `size` returns pair; delete dead chart GET cases 3941–3958 except `chartdata` (3959); masking (3778–3783) preserved inside the helper.
- `formatAllProperties` (6235): rewrite to iterate registry descriptors applicable to the part (aiExposed only), rows via `partPropertyReadValue`, `aliases:` annotation, `defaultDescription`, legacy names listed under an explicit `## Legacy / not scriptable` note (names only, no values); keep header/footer lines and the `(masked)` behavior.
- `boolArgument`: keep; unify all `== "true"` sites listed in the audit through the gate.

**`Sources/HypeCore/AI/HypeTools.swift`** (972–1004, 1213–1229): update `set_part_property`/`get_part_property`/`list_all_properties` descriptions — canonical vocabulary, strict unknown/wrong-type errors, `size` note.

**`Sources/Hype/Views/PropertyInspector.swift`** — all labels per design-mock §2.3/§2.4, verified sites: display names at 74, 936, 981, 1009, 1058, 2096, 3625, 4294. Helpers 5275/5289 gain `placeholder:`/`unit:`. Section by section: common (932): "Position" header → "Position & Size"; button (976): Label caption, conditional Hilite row (styles toggle/checkBox/radio); field (1004): "Content"→"Contents" (1043), conditional search block (Prompt = searchPrompt, Search While Typing = searchSendsImmediately + caption); shape (1053): "Shape"→"Style", new Rotation (+"°"); image (1079): new Rotation; video (1148): "URL/Path"→"Source" (1151, placeholder "File path or URL"), new Autoplay/Loop/Volume(0–1 slider)/Play Rate(+"×"); calendar (1164): Date/Time/Display Month placeholders `yyyy-MM-dd`/`HH:mm:ss`/`yyyy-MM`; pdf (1187): "URL/Path"→"Source" (1190), "Mode"→"Display Mode" (1199), "Auto-scale to fit"→"Auto-Scale to Fit" (1209); map (1238): "Span (deg)"→"Span"+"°" (1243), "Annotations JSON"→"Annotations" (1269), new Show User Location + caption; stepper/slider (1285): header via sectionHeading (1287); segmented (1302): "Segments (pipe-separated)"→"Segments"+caption (1305), "Selected Index"→"Selected Segment"+caption (1306); scene3D (1310): "Resolved"→"Resolved Path" (ro), "Default Lighting"→"Auto Lighting" (1360), "Anti-aliasing"→"Anti-Aliasing" (1364); audioRecorder (1506): colon rows 1538/1544 → `propertyRow(_:value:)`, duration "2.4 s"; synth (1551): Show Control Type / Show Pattern Name / Show Instrument Popup / Show Tempo toggle labels (fix 1554/1577, 1596/1579 double-labeling), new Tracks (ro, parsed count from musicTrackData; "(none)" on parse failure) for stepSequencer/musicMixer + caption; appleMusic (1615): header "MusicKit Search"→"Apple Music" (1617), prose 1587, "Music Type"→"Type", "Artist / Singer"→"Artist" (1647) and `appleMusicDisplayName(.artist)`→"Artist" (1797), Position/Duration + "s"; progress (1823): "Total"→"Max" (1831) + captions; gauge (1857): style picker Title Case (abbreviation exception documented); divider (1906): Thickness + "pt"; spriteArea (2013): headers 2075/2112/2121/2141/2148 via sectionHeading; chart (4286): Type display names (4294), "Interactable"→"Interactive" (4303), Grid/Axis/Labels → Grid Color/Axis Color/Label Color (4364–4366), Minimum/Maximum → Min/Max (4465/4470); text formatting (4189): "Color"→"Text Color" (4213 region). Multi-select (280–474): "BEHAVIOR"→"State" (351), header strings to Title Case, "Stroke W"/"Corner R" (375/376) → stacked full-word rows, text "Color"→"Text Color" (~411). Node multi (3246–3343): W/H→Width/Height, Rot→Rotation, zPos→Z, xScale/yScale→Scale X/Scale Y, Hidden→Visible inverted (3294), Font Color→Text Color (3335). Node single: headers 3494/3544/3548/3551/3569/3604/3621/3638/3667/3697/3779 via sectionHeading (Title Case input), Hidden→Visible (3512), label Color→Text Color (3616), shape node picker label→"Style" (3621–3625), physics "Gravity"→"Affected by Gravity" (3795), "Rotation"→"Allow Rotation" (3797). Accessibility labels on every touched labels-hidden control (precedent 4455/4496); unit spelled out in the a11y string ("Span, degrees").

**`Sources/HypeCore/AI/HypeTalkGuide.swift`** + **`HypeTalk-LLM-Context.md`**: Decision 6.

## Compatibility analysis

Verified against the tree (test-explorer sweep): (1) `size` — no script-level test uses `set the size`/`the size of`; all `textSize` references are direct field access; AI GET `size` change touches no test. (2) Strict-SET — no test asserts variable-fallthrough; AI surface already errors. (3) min/max/step — GaugeTests uses explicit `gaugeMax`; chart data-point min/max ride `applyChartDataPointSet` (separate path, untouched). (4) Bare `volume` on music parts pinned by AudioKitMusicTests:274/327 — kept by the music-family cells. `duration` on video/audioRecorder pinned by Phase5VideoTransportTests — kept (read-only, which they only read). (5) `marked`/`icon` — no tests. (6) Window shim (`applyHyperCardWindowPropertySet`) untouched; its parse/exec tests unaffected. (7) HyperCard importer writes fields directly (HyperCardToHypeConverter.swift:388–404) — immune; no-op stubs stay for imported scripts. (8) list_all_properties string-presence tests (Phase1ControlsTests:446–484, ProgressViewTests:342–363, TextStylingTests:373–377, HelpTextTests:189–193) — format changes; update deliberately, keeping canonical names + alias annotations visible (e.g. progress `max` row annotated `aliases: total, progressTotal`). (9) PropertyAuditTests — all properties it exercises remain recognized; it gains the strict-SET negatives. (10) Fuzzer generates no property statements today — extended, not broken. (11) Stored named-color/garbage values in existing documents load and render exactly as before (validation is write-time only); writes of named colors now error (declared strict posture). (12) AI `location` on non-map parts stops writing the dormant mapLocation field (silent wrong-write killed; noted in docs). (13) No `.hype` shape change → no migration workflow needed.

## Test plan (mock §8 criteria → tests)

1. Round-trip — `PartPropertyRegistryConformanceTests.swift`: iterate descriptors × applicable fixture part; per ValueKind seeded sample values; HypeTalk set→get via MessageDispatcher and AI set→get via executor; assert get==normalized(set) (clamping kinds assert in-range round-trip).
2. Alias symmetry — same file, from registry (+ alias-uniqueness across descriptors).
3. Dispatch cells — `PartPropertyDispatchTests.swift`: parameterized cell tests (bare set → long-name read); error cells assert `.error` with property+type in message.
4. size — dispatch tests, both surfaces, error copy exact.
5. Strict-SET — PropertyAuditTests additions: typo errors with hint; follow-up read proves no variable; 12 stubs no-op.
6. Wrong-type — dispatch tests both surfaces (gaugeValue on button et al.).
7. H-regressions — dispatch tests: H1, H4 (+card path still works), H5, H8 (`is empty` true), H9.
8. Boolean parser — AI tests: token/case/whitespace fuzz loop (seeded); `"1"`→visible; garbage errors.
9. Chart single path — non-chart `charttype` errors; chart `title`/`interactive` work; source-scan asserts dead cases gone.
10. A5 closures — dispatch tests get+set both surfaces.
11. list_all_properties — conformance test: two-direction diff vs registry per part type; masked secure field.
12. Docs — HypeTalkGuideTests two-direction walk (Decision 6).
13. Display names — `PartDisplayNamesTests.swift`: exact table equality over CaseIterable.
14–18, 20 — `PropertyInspectorLabelSpecTests.swift` source-scan (Decision 7).
19, 21 — Designer Sign-off visual checklist (mock §8 note); source-scan asserts row constructs + conditions exist.
Fuzz — extend `InterpreterFuzzTests.swift` ScriptGen: fixture doc gains one part per major type; new `propertyStmt()` emits `set the <name> of <target> to <expr>` / `put the <name> of <target> into x` with name pool = canonicals + aliases + near-miss typos + bare polymorphic names; oracles stay no-crash + determinism (ScriptError completion is a valid outcome); failures pin seeds in `regressionSeeds`.
Performance — `docs/HypeTalkBenchmarkBaseline.md` property-access workload (release, `--benchmark-iterations 50`), before+after, median of 3 runs, commands shown; baseline 194.734 ms total / 3.895 ms avg; >5% regression blocks.

## Work packages (order)

P1 registry + HypeTalk + core tests + fuzz → P2 AI surface + parity tests → P3 inspector + label-spec tests → P4 docs + docs conformance + evidence. Each ends with a green `scripts/test.sh` (real, non-zero counts). Rationale: registry is the dependency root; AI reuses resolution + the read helper; the inspector depends only on display names but lands after core stabilizes to keep churn away from the interpreter diff; docs must describe the final surface. Tasks.md carries the checklist.

## Risks / Trade-offs

- [Hot path] +1 dictionary lookup per property access → benchmark gate (above); no per-call allocation; error-path-only Levenshtein.
- [Big interpreter diff] → hybrid keeps semantics in place; conformance tests catch registry/switch drift; alias labels stripped only where shadowing is possible (listed).
- [Headless UI coverage] → source-scan tests + explicit Sign-off checklist; app target still compiled by the pre-push gate.
- [Swift 6] → registry is immutable value-type data, no closures/locks; `PartPropertyError` Sendable.
- [-Osize] → pure-data registry, ~50 dead lines deleted; record release size delta in Deploy evidence (budget: no Interpreter.o growth beyond ~2%).
- [Existing list-format tests] → four suites updated deliberately with rationale in the diff.
- [Mock errata] → SpriteShapeType case mismatch; TargetRuntimeControlViews.swift:1169 is the tvOS field view (macOS runtime button label is 960–963: `showName ? name : textContent`, literal "Button" fallback) — Builder verifies the button-Label caption wording against the editor's ButtonRenderer and flags divergence to the Designer instead of silently shipping a false caption.
- [Residual typo-swallowers] → target-not-found SET fallback (1603–1605) and unknown-name GET `""` stay; documented, recommended follow-up.

## Conditions for Builder

1. **Masking law (Security Finding 1 — closes a live vulnerability, lands in THIS change):** every alias of the `textContent` canonical on `.field` parts — `text`, `textcontent`, `value`, and the new `contents` — must resolve through the single masked switch cell on BOTH surfaces. Today `value` bypasses masking (HypeToolExecutor.swift:3827-3835, Interpreter.swift:5667-5677 — no `.secure` check); the registry's canonical-keyed dispatch fixes this structurally, and the Builder must NOT transcribe the old unmasked `value` branch as a separate case. Enforcement: a registry-driven masking-law test in `Tests/HypeCoreTests/SecurityRegress **Field-body-text masking set (mask-change Security Findings 3 + re-review):** three field-text properties can hold a secret on a `.secure` field and each has a curated getter that returns plaintext today: `textContent` (aliases text/textcontent/value/contents), `htmlContent` (htmlcontent/html_content, Interpreter.swift:5910, HypeToolExecutor get), and `searchText` (searchtext/search_text, Interpreter.swift:5805, HypeToolExecutor.swift:3988). The registry declares a **`secureMasked` flag** on these three descriptors; the GET path returns "(masked)" for `.field`+`.secure` parts on BOTH surfaces for every alias of all three. The masking-law test is registry-driven: it iterates EVERY descriptor whose `secureMasked` is true and asserts "(masked)" for a `.secure` field across all its aliases on both surfaces — so a fourth masked property added later is covered by test structure, not a hand-updated list. (Security's exhaustive sweep of Part's ~90 String fields confirmed these three are the complete field-body set; `searchPrompt`/`helpText` are author-set chrome, not secret-bearing.) Also: masking preserved verbatim at `get_part_property`, `formatAllProperties`, any new helper; no new unmasked path; error messages and did-you-mean hints must never echo property VALUES — names only.
2. Strict-SET must not alter: `set <var> to <expr>` with no object target; global/env property sets; the window shim; scene/node/scene-object paths; card/background/stack property sets; the target-not-found fallback at Interpreter.swift:1603–1605.
3. The 11 classic no-op stubs + `scroll`/`scrollpos` remain accepted no-ops via `.noOpStub` declaration — they must never reach the unknown-property error (imported classic stacks).
4. The `script` property's AI-side gates are untouched: wrapScript + refusalForInvalidDraft + sprite-scene routing (2212–2258); the registry gate runs before but never bypasses or duplicates them. NOTE (Security Finding 5): the interpreter's own script SET (Interpreter.swift:7482) has NO validation gate today — a raw same-trust write; the Builder must not "preserve" a nonexistent gate, and must verify registry resolution does not introduce asymmetric gating between the two surfaces. `menuItems` parse validation + 64 KB cap preserved on both surfaces.
5. No stored Codable key changes, no `Part` field renames, no document-version bump, no `.hype` rewrites; the registry is dispatch metadata only.
6. `HexColor` accepts exactly {"", 6-digit, 8-digit hex, optional #} and stores normalized `#UPPER`; it is NOT applied to chart spider colors — `ChartConfig.normalizedHex` and every chart path stay byte-identical.
7. Preserve exactly: GIFAnimator main-thread dispatch in `animated` SET (race fix, 7593–7623); videoPlayRate NaN/Inf clamp (7628–7633); every `String(value.prefix(N))` cap; `setProgressValue`/`setGaugeValue` routing; gaugeMax>gaugeMin repair; progressTotal 1e-10 floor.
8. `min` on progressView SET accepts only 0 (exact copy per tables); GET returns "0".
9. Registry is `static let`, immutable, `Sendable`, value types only — no closures capturing env/document/context, no locks, no lazy mutable state.
10. Strip bare polymorphic aliases from hand-written case labels wherever the registry declares dispatch (`size` from the textsize labels on all three switch sites; `loop`/`looping`, `volume`, `tint`, `prompt`, `items`, `total` from their current host cases) — a stale label must never shadow a resolved canonical. The dispatch-cell tests are the proof.
11. Error copy exactly as specified (including the mock-verbatim `size`, progress-min, and `marked` messages); suggestions computed only over names applicable to the target's partType, distance ≤ 2. Echoed property names are capped at `String(rawName.prefix(200))` in all error copy (Security Finding 4 — consistency with the codebase's `.prefix(N)` discipline).
12. Chart interception sets (`chartLevelProperty`/`setChartLevelProperty`, `chartPropertyValue`/`applyChartProperty`) must cover `interactive`/`interactable` and `title` BEFORE the registry gate so chart parts never hit the colorWell-scoped `interactive` or name-scoped `title` descriptors.
13. The interpreter fuzz suite must stay green and be extended per the test plan; any discovered failure seed is pinned in `regressionSeeds` before the fix lands.
14. Benchmark evidence: property-access workload before+after (release, 50 iterations, median of 3, commands shown); >5% regression blocks the phase.
15. `list_all_properties` is registry-generated: zero missing, zero phantom vs the registry; legacy entries named under the explicit legacy note without dumping values (`htmlContent` renders name-only).
16. Both docs update together (AGENTS.md rule) with breaking-change notes for `size` and strict-SET; the docs conformance test is the enforcement, not prose diligence.
17. Do not modify `HypeMCPDocumentBackend` masking behavior in this change — the object-tool masking asymmetry is **tracked as a required immediate follow-up change (Security-flagged HIGH, plan-stage Finding 2)**: mask `.secure` field `textContent` at `getObject`/`fullDocumentResource`/`hype_get_stack_document` before `codableJSONValue`, and rule explicitly on whether `replacePart` re-runs field-level validation. Security re-reviews that change when it lands. Not an open-ended residual.
18. **Must-stay-green suites (Security Finding 3):** `Tests/HypeCoreTests/SecurityRegressionTests.swift` (masking, clamps, caps) and `Tests/HypeCoreTests/ScriptStorageGateIntegrationTests.swift` (script storage gate, incl. `set_part_property property="script"` at ~184–230) pin Conditions 1/4/7 — any failure there is an automatic blocking regression at Security (code), not something to rationalize.
