# Control Property Consistency

## Purpose

A Hype part's properties are reachable four ways — the Properties Inspector, HypeTalk (`get`/`set the <property> of <part>`), the AI tools (`get_part_property`/`set_part_property`/`list_all_properties`), and the two AI-facing docs (`HypeTalkGuide.swift`, `HypeTalk-LLM-Context.md`). A four-surface audit (`audit-synthesis.md`) found that the same concept wore different names on different surfaces (button "Label" vs. field "Content" vs. HypeTalk `textContent`; nine spellings of "color"), some properties were reachable on only one surface (video playback, `popupItems`, `mapShowsUserLocation`), and — worse than drift — several names silently did the wrong thing: `set the size of <part>` wrote `textSize` instead of geometry; `set the max of gauge "T"` wrote an unused `controlMax` field instead of `gaugeMax`; GET `style` of a shape returned field-style garbage while SET wrote the correct field; `the value of a secure field` returned its plaintext content, bypassing the masking the AI tools otherwise applied; and any SET of a misspelled property silently created a script variable instead of erroring, so typos vanished without a trace. This change unifies all four surfaces plus the docs onto one vocabulary.

## Value

One property vocabulary, spoken identically everywhere, driven by a single `PartPropertyRegistry` (`Sources/HypeCore/Models/PartPropertyRegistry.swift`) and enforced by mechanical conformance tests, so the four surfaces cannot drift apart again the way they did before. The secure-field masking leak is closed structurally — every alias of a masked property routes through the same registry-declared cell on both script surfaces, not a hand-maintained list that a new alias could bypass. HypeTalk and the AI tools now have genuine parity: byte-identical error copy for unknown/wrong-type/read-only properties, and cross-surface equivalence enforced by tests (`CrossSurfacePropertyEquivalenceTests`, `PartPropertyRegistryConformanceTests`, `PartPropertyDispatchTests`). The Inspector gains consistent, accessible labels — no more `PartType.rawValue` leaking into the UI as "Musicplayer" or "Colorwell", no more the same range concept called "Min/Max" here and "Minimum/Maximum" there.

## Scope

**In scope**: the `PartPropertyRegistry` (canonical names, aliases, applicability, mutability, value kind, secure-masking flag); HypeTalk GET/SET dispatch (`Interpreter.swift`); the AI tool surface (`set_part_property`, `get_part_property`, `list_all_properties` in `HypeToolExecutor.swift`); Properties Inspector labels and display names (`PropertyInspector.swift`, `PartDisplayNames.swift`); the two AI-facing docs. All of it is presentation/dispatch-layer.

**Out of scope**:
- No stored `Part` field renames, no `Codable` key changes, no `.hype` document-version bump. The registry is dispatch metadata only — it resolves a spoken name to the same stored field that already existed.
- Secure-field masking for the MCP object tools (`hype_get_object`, `hype_replace_part`) is a separate, tracked follow-up change (`mask-mcp-object-tools`) — this change does not touch `HypeMCPDocumentBackend`.
- Deferred (documented in design-mock.md §7, not addressed here): an icon-picker UI for `iconId`; a real sequencer/mixer track editor for `musicTrackData` (the Inspector now shows a read-only track count); a `pdfAssetRef` AI binding tool (parity with scene3D's binding); the target-not-found SET fallback (`Interpreter.swift:1605-1607`, unrelated residual typo-swallower) and GET of a fully unknown property name (stays `""`, unchanged — only SET became strict).

## Functional details

**The registry.** `PartPropertyRegistry` declares every scriptable property once as a `Descriptor`: `canonical` (the lowercase dispatch key), `aliases` (every other spelling — identical between GET and SET by construction), `getApplicability`/`setApplicability` (which part types, `nil` = universal), `mutability` (`getSet` / `readOnly` / `noOpStub`), `kind` (`string`/`number`/`boolean`/`color`/`pair`/`enumeration`/`json`), `aiExposed`, `legacy`, and `secureMasked`. It is a `static let`, all value types, `Sendable` — no closures over `env`/`document`/`context`, so it is strict-concurrency clean. Resolution is one dictionary lookup on the already-lowercased name per property access; the hand-written GET/SET switches keep implementing the actual semantics, now keyed on the canonical name the registry resolves to (a hybrid, not a full rewrite — see design.md Decision 1).

**Polymorphic dispatch.** A small set of bare, ambiguous words — `value`, `on`, `min`, `max`, `step`, `loop`, `volume`, `autoplay`, `duration`, `tint`, `prompt`, `total`, `items`, `decimals`, `color`, `style`, `background` — resolve per the target part's type before the flat registry lookup ever runs. (Type-scoped names like `playRate`, `currentTime`, and the `contents` alias of `textContent` are ordinary descriptors, not polymorphic bare words.) For example, bare `min`/`max` map to `controlMin`/`controlMax` on stepper/slider, `gaugeMin`/`gaugeMax` on gauge, `minDate`/`maxDate` on calendar, and (max only — min is pinned to 0) `progressTotal` on progressView; any other part type errors naming the property and listing the types it does apply to. Long, type-prefixed names (`gaugeMax`, `videoLoop`, …) always work directly regardless of the bare-word table.

**The size pair law.** `the size of <part>` is the geometry pair on both verbs: GET returns `"width,height"` (unchanged) and SET now accepts `"width,height"` and writes width/height (previously SET silently wrote `textSize`, an unrelated field). A non-pair SET value errors, naming `textSize` as the property to use for text size instead. This is the one deliberate breaking change to a stored write path (no format change).

**Strict SET.** SET of an unrecognized property name on a resolvable object target is now a runtime error containing the property name and the object's type, with a nearest-match hint (Levenshtein distance ≤ 2, scoped to names applicable to that part's type) when a close candidate exists — e.g. `no such property "gaugvalue" for gauge "T" — did you mean "gaugevalue"?` (the suggestion is drawn from the registry's lowercase canonical/alias strings, not re-cased). Previously it silently created a script variable (`env.setVariable`), so a typo produced no error and no effect. The 11 classic HyperCard no-op field stubs (`sharedText`, `sharedHilite`, `showLines`, `showPict`, `fixedLineHeight`, `multipleLines`, `dontSearch`, `autoSelect`, `autoTab`, `cantDelete`, `cantModify`) plus `scroll`/`scrollPos` remain accepted no-ops by explicit `.noOpStub` declaration, so imported classic stacks that reference them keep working without error. Plain `set <var> to <expr>` with no object target is untouched — this only affects `set the <property> of <object> to <value>`.

**Wrong-type writes.** A type-scoped property (the gauge\*/progress\*/video\*/music\*/calendar/pdf\*/map/colorWell/scene3D\*/segmented/search-field/field-flag/image-flag/icon/chart-key families) now errors when set on a part type outside its declared applicability, instead of silently mutating a field the part never renders — e.g. setting `gaugeValue` on a button errors naming `gaugeValue` and `button`. GET of long, type-prefixed names stays permissive (a harmless stored-field read), matching the documented GET-leniency decision (design.md Decision 3): SET is where strictness was needed, since only SET can corrupt state.

**Secure-field masking.** Three field-body properties can hold secret content on a `.secure` field: `textContent` (aliases `text`, `textcontent`, `value`, `contents`), `htmlContent`, and `searchText`. Each is declared `secureMasked: true` in the registry; GET returns `"(masked)"` for all of their aliases on a `.secure` field, on both the HypeTalk and AI surfaces. Previously, `value` bypassed masking entirely on both surfaces (no `.secure` check on that code path) — the registry's canonical-keyed dispatch closes this structurally, because every alias of `textContent` now resolves through the one masked switch cell rather than a separate unmasked branch. `searchPrompt` and `helpText` are deliberately excluded from masking — they are author-facing chrome (placeholder text, a tooltip), never secret-bearing.

**Display names.** `PartDisplayNames.swift` provides hand-written, exhaustive (no `default:`) `displayName` mappings for `PartType`, `ButtonStyle`, `FieldStyle`, `ShapeType`, `SpriteShapeType`, `ChartType`, and `SceneScaleMode`, so the Inspector never renders a raw `.rawValue` or `.capitalized` string (previously: "Musicplayer", "Colorwell", "checkBox", "roundRect" leaking into the UI).

**Vocabulary rules applied to the Inspector** (design-mock.md §1–§2): color rows are labeled by role (Fill / Stroke / Text Color / Tint / Background), with bare "Color" reserved for parts with exactly one color; range rows use Min/Max/Step uniformly (progress's "Total" retired in favor of "Max", matching its siblings — the stored field `progressTotal` is unchanged); "Content" becomes "Contents" (the classic HyperCard term) for field body text; enum-variant pickers use one word per category (Style / Type / Mode / Format); booleans are positive-polarity and verb-prefixed (`Show X`, `Allow X`, `Auto X`) except for HyperCard's own classic negatives (`Lock Text`, `Don't Wrap`, `Auto Hilite`), which are kept verbatim as a documented exception; units render as trailing secondary text next to the field, never inside the label; no row label ends in a colon.

**Breaking changes**:
1. `set the size of <part>` now takes `"width,height"` and writes geometry (was: silently wrote `textSize`). Use `textSize` to set text point size.
2. SET of an unknown property on an object target now errors instead of silently creating a script variable.

## Usage

The same property now works identically across all three author-facing surfaces.

**1. A regular color property — `fillColor` on a shape:**

HypeTalk:
```
set the fillColor of shape "box" to "#FF0000"
```

AI tool call:
```json
{
  "tool": "set_part_property",
  "part_name": "box",
  "property": "fillcolor",
  "value": "#FF0000"
}
```

Inspector: the Shape section's **Fill** color row (swatch + hex field), same stored field (`fillColor`), same normalized `#FF0000` on disk either way. An invalid value (e.g. `"reddish"`) errors on both script surfaces instead of storing garbage; `""` clears to auto.

**2. Polymorphic dispatch — bare `max` on a gauge:**

```
set the max of gauge "g" to 100
```
`the gaugeMax of gauge "g"` now returns `100`, and the unrelated `controlMax` field is left untouched (previously the bare form silently wrote `controlMax`, which the gauge never reads). The same bare `max` on a stepper or slider instead dispatches to `controlMax`; on a part type with no range concept (e.g. a button), both HypeTalk and `set_part_property(part_name:, property:"max", value:)` error, naming the property and the part's type.

**3. Secure-field masking — reading a secure field's contents:**

```
get the value of field "password"  -- fieldStyle is .secure
```
returns `"(masked)"` rather than the field's real text. `set_part_property(part_name:"password", property:"value", value:"...")` still writes normally (masking applies to reads); `get_part_property(part_name:"password", property:"textContent")` and `...property:"searchText"` and `...property:"htmlContent"` on a secure field are masked the same way, on both surfaces. (Masking keys on `fieldStyle == .secure`; a `.search`-style field is a different, unmasked style — the two are mutually exclusive.)

**4. The size pair law:**

```
set the size of button "OK" to "120,48"
get the size of button "OK"       -- returns "120,48"; width=120, height=48
set the size of button "OK" to 24 -- errors: size expects "width,height" — use textSize to set the text size.
```
The AI surface's `set_part_property(part_name:"OK", property:"size", value:"120,48")` round-trips identically; a non-pair value produces the same error copy naming `textSize`.
