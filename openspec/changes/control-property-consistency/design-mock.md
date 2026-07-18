# Design Spec — `control-property-consistency`

**Phase:** Design Mock (pre-Architecture) · **Designer** (Fable) · 2026-07-17
**Grounding read:** `openspec/changes/control-property-consistency/audit-synthesis.md`, `Sources/Hype/Views/PropertyInspector.swift` (all cited label sites), `Sources/HypeCore/Models/Part.swift`, `Sources/HypeCore/Models/HypeStack.swift`, `Sources/HypeCore/Script/Interpreter.swift` (GET dispatch region), button label resolution at `Sources/HypeCore/Rendering/ButtonRenderer.swift:162` (editor) and `Sources/HypeCore/Export/TargetRuntimeControlViews.swift:960-963` (exported runtime). *(Citation corrected at Review — see Revision log.)*

**Hard constraint honored throughout:** no stored `Part` field renames; `.hype` Codable keys are untouched. Every reconciliation below is presentation-layer only: inspector labels, HypeTalk names/aliases, AI keys, docs.

---

## 0. Intent, in the project's language

Hype is a HyperCard revival. A part has *properties*; the author reaches them three ways — the Properties Inspector, HypeTalk (`get`/`set the <property> of <part>`), and the AI tools (`get_part_property`/`set_part_property`/`list_all_properties`). Today the same property wears different names on different surfaces, some properties are reachable on only one surface, and some names silently do the wrong thing. The change makes **one vocabulary, spoken identically on all four surfaces**, with classic HyperCard terms as the ubiquitous language wherever classic precedent exists (`style`, `hilite`, `Auto Hilite`, `Lock Text`, `Don't Wrap`, `Contents`, `Show Name`, `textSize`).

## 0.1 Existing design language to reuse (do not invent parallels)

From `PropertyInspector.swift`:

| Pattern | Site | Rule |
|---|---|---|
| `sectionHeading(_:)` — 10pt bold uppercase | PI:924-929 | The ONLY section-header treatment. All hand-rolled headers migrate to it. |
| `propertyRow(label, binding:)` — 60pt trailing label + text field | PI:5275 | Text properties. Gains optional `placeholder:` and `unit:` parameters (see §1.6). |
| `propertyRow(label, value:)` — read-only | PI:5282 | All read-only values (replaces the ad-hoc colon rows at PI:1538/1544). |
| `numberField(label, binding:)` — compact 10pt label + 60pt field | PI:5289 | Numeric properties. |
| `colorPropertyRow(label:…)` — swatch + hex field | PI:5251 | Every stored hex color, no exceptions ("One pattern, all parts" — its own doc comment). |
| Tempo unit idiom — field + trailing secondary unit `Text` ("BPM") | PI:1595-1605 | The canonical way to show units (§1.6). |
| Conditional sub-block (popup items only when `.popup`) | PI:989-998 | Style-scoped rows (hilite, search props). |
| "Multiple" placeholder in multi-select | PI:5037+ | Mixed-value state everywhere. |
| Sentinels: picker "— None —", read-only "(none)", caption "Empty = system accent color" | PI:1320, 1358, 1834 | Keep exactly these three forms. |
| `.help(…)` tooltips + `accessibilityLabel` on label-hidden fields | PI:1101, 4455, 4496 | Required on every `labelsHidden()` control (§6). |

---

## 1. Canonical concept vocabulary

One term per concept, one concept per term. Classic HyperCard vocabulary wins wherever it exists.

### 1.1 Color roles

Rule: **a color row is labeled with its role.** Bare "Color" is allowed only when the part has exactly one color (Color Well, Divider). Append "Color" when the role word alone could read as a different control (a toggle or a count).

| Role | Inspector label | HypeTalk canonical (aliases kept) | Stored field |
|---|---|---|---|
| Interior of a drawn part | **Fill** | `fillColor` (`fillcolor`, `fill_color`) | `fillColor` |
| Outline | **Stroke** | `strokeColor` | `strokeColor` |
| Rendered text | **Text Color** (everywhere: part Text Formatting PI:4213, multi PI:411, label-node single PI:3616, label-node multi PI:3335) | `textColor` — new canonical, `fontColor`/`fontcolor`/`font_color` remain as compat aliases | `fontColor` / node `fontColor` |
| Accent of a system-drawn control | **Tint** (gauge, progress) | `gaugeTint` / `progressTint`; bare `tint` dispatches by type (§3.3) | `gaugeTint`, `progressTint` |
| Behind hosted content | **Background** (3D Scene) | `background` (short) / `sceneBackground` | `scene3DBackground` |
| The part's own single color | **Color** (Color Well, Divider) | `color` | `colorWellHex`, `dividerColor` |
| Chart spider colors | **Grid Color / Axis Color / Label Color** (fixes bare "Grid"/"Axis"/"Labels", PI:4364-4366) | existing chart keys | ChartConfig |
| Particle color | **Particle Color** (unchanged, PI:3725) | — | EmitterSpec |

Additionally: every color write on the HypeTalk/AI surfaces validates through one shared hex validator (the `ChartConfig.normalizedHex` behavior generalized); malformed hex errors instead of storing garbage. (Closes the M1-1/M2 "only charts validate" gap at the presentation layer.)

### 1.2 Range and Value

- Canonical range words: **Min / Max / Step** (short forms — the dominant existing usage). "Minimum"/"Maximum" (spider, PI:4465-4471) become "Min"/"Max". "Min Date"/"Max Date" keep the noun because the bare word would be ambiguous in the Calendar section.
- **Progress "Total" is retired from the vocabulary.** Inspector label becomes **Max** (PI:1831); the concept caption: "Progress runs from 0 to Max." HypeTalk/AI: `max` dispatches to `progressTotal` (§3.2); `total`/`progresstotal` stay as compat aliases. Justification: Min/Max is the range concept on every sibling control; storage key `progressTotal` is untouched.
- Canonical value word: **Value**. Segmented control is the one true exception: its row is **Selected Segment** (was "Selected Index", PI:1306) — it matches the existing HypeTalk property `selectedSegment` verbatim (name/code lockstep), with caption "0 = first segment."

### 1.3 Caption family

| Term | Meaning | Where |
|---|---|---|
| **Name** | Scripting identity of the part | Identity section (unchanged) |
| **Label** | Short text drawn on/near a control | Button face text (`textContent` on buttons — caption: "Shown on the button when Show Name is off." — matches renderer behavior at ButtonRenderer.swift:162, `showName ? name : textContent`; an empty label draws a blank face), `gaugeLabel`, `progressLabel`, chart axis labels ("X Label"/"Y Label") |
| **Contents** | The user-editable body text of a field | Field section (was "Content", PI:1043). Classic HyperCard term — HyperCard's dialog and HyperTalk both said "Contents". HypeTalk: `contents` joins the alias set for field `textContent`. |
| **Title** | Heading of a content surface | Chart title, Apple Music item title |
| **Prompt** | Placeholder shown when empty | Search field `searchPrompt` |

### 1.4 Enum-variant chooser words

One word per category, one category per word:

| Word | Category | Applied to |
|---|---|---|
| **Style** | Visual variant of the same control (classic HyperCard: `the style of`) | Button, Field, Shape (was "Shape"/"Type" split, PI:1056 vs 3623 — unified because HypeTalk SET already treats `style` of a shape as `shapeType`, IP:7469-7479), Calendar, Gauge |
| **Type** | Kind of content/data | Map, Chart, Apple Music item ("Music Type" → **Type**), shape *node* picker (PI:3623) also becomes **Style** to match the part surface |
| **Mode** | How content is viewed | PDF → **Display Mode** (was "Mode"; matches HypeTalk `displayMode`) |
| **Format** | Data encoding | Audio Recorder format |
| **Orientation** | Spatial axis | Divider |
| Own noun | Technical settings keep their name | "Anti-Aliasing", physics "Body", scene "Scale" |

### 1.5 Boolean phrasing and polarity

1. **Positive polarity; verb-prefixed**: `Show X` (sub-element visibility), `Allow X` (capability), `Auto X` / `Auto-` (automatic behavior), `Enable X` (feature switches). Never a bare ambiguous adjective, never a new negated label.
2. **Classic exemption**: HyperCard's own negatives/locks stay verbatim — **Lock Text**, **Don't Wrap**, **Auto Hilite**, **Show Name**, **Hilite**. Classic vocabulary is the ubiquitous language; renaming it is the greater harm. The "Interactive vs Lock Text" polarity clash flagged in the audit is therefore a *documented deliberate exception*, not drift.
3. **Terms of art** may stand bare when they are the industry word and both surfaces use them: **Interactive** (Color Well and chart — "Interactable" at PI:4303 is renamed **Interactive** to match the HypeTalk/AI key `interactive`), **Indeterminate**, **Dynamic** (physics), **Autoplay**, **Loop**.
4. Part visibility is **Visible** (classic). Scene-node "Hidden" toggles (PI:3294, 3512) flip to **Visible** with an inverted binding — one inspector, one polarity for one concept.

### 1.6 Units presentation

One strategy: **units render as a trailing secondary `Text` after the field** — the existing Tempo/BPM idiom (PI:1595-1605). Never in the row label, never as a label parenthetical.

- "Span (deg)" → **Span** + trailing "°"; "Thickness (pts)" → **Thickness** + "pt"; "Position Seconds"/"Duration Seconds" → **Position**/**Duration** + "s"; Rotation rows get "°"; video Play Rate gets "×".
- **Input-format hints move to the text-field placeholder**, not the label: "Selected (yyyy-MM-dd)" → **Date** with placeholder `yyyy-MM-dd`; "Selected Time (HH:mm:ss)" → **Time** with placeholder `HH:mm:ss`; Display Month placeholder `yyyy-MM`. `propertyRow` gains optional `placeholder:` and `unit:` parameters to carry this (single helper change, reused everywhere).
- Read-only values format the unit into the value ("2.4 s", "128 KB") — already the pattern; keep.
- Justified exception: none. Format examples that don't fit a placeholder (map annotations JSON) stay in the existing 9pt caption line.

### 1.7 Label style rules

- **Title Case** for all row labels and toggles, Apple-style (articles/prepositions lowercase): "Auto-Scale to Fit" (PI:1209), "Save Recordings in Stack", "Affected by Gravity", "Show User Location".
- **No trailing colons** (fixes PI:1538, 1544 — both become `propertyRow(_:value:)` rows).
- Captions/hints: sentence case, 9pt secondary, ending period (existing idiom).
- `sectionHeading()` receives Title Case text (it uppercases itself).
- **No `rawValue` or `.capitalized` ever reaches a rendered string.** Every enum shown in UI goes through a hand-written display-name mapping (§2.1, §2.2).

---

## 2. Inspector label spec

### 2.1 PartType display names (fixes I1 — PI:74 headline and PI:936 Type row)

Complete mapping; the same strings are used by headline, Type row, and section headers (one source of truth, e.g. `PartType.displayName` — exhaustive `switch`, no `default`, so the compiler enforces completeness for future cases):

| rawValue | Display name | | rawValue | Display name |
|---|---|---|---|---|
| button | Button | | audioRecorder | Audio Recorder |
| field | Field | | scene3D | 3D Scene |
| shape | Shape | | musicPlayer | Music Player |
| webpage | Web Page | | pianoKeyboard | Piano Keyboard |
| image | Image | | stepSequencer | Step Sequencer |
| video | Video | | musicMixer | Music Mixer |
| chart | Chart | | appleMusicBrowser | Apple Music Browser |
| spriteArea | Sprite Area | | musicQueue | Music Queue |
| calendar | Calendar | | progressView | Progress View |
| pdf | PDF | | gauge | Gauge |
| map | Map | | link | Link *(legacy)* |
| colorWell | Color Well | | menu | Menu *(legacy)* |
| stepper | Stepper | | searchField | Search Field *(legacy)* |
| slider | Slider | | divider | Divider |
| toggle | Toggle *(legacy)* | | unknown | Unknown |
| segmented | Segmented Control | | | |

### 2.2 Enum-case display names (fixes I2 — PI:981, 1009, 1058, 3625, plus rawValue pickers at PI:2096 SceneScaleMode and PI:4294 ChartType)

- **ButtonStyle** (picker order preserved): standard "Standard", default "Default", shadow "Shadow", transparent "Transparent", oval "Oval", toggle "Toggle", link "Link", checkBox "Check Box" (classic spelling), popup "Popup", radio "Radio"; non-picker cases for completeness: opaque "Opaque", roundRect "Round Rect" (classic spelling).
- **FieldStyle**: transparent "Transparent", rectangle "Rectangle", shadow "Shadow", scrolling "Scrolling", secure "Secure", search "Search". (Matches classic field-style vocabulary.)
- **ShapeType**: rectangle "Rectangle", roundRect "Round Rect", oval "Oval", line "Line", freeform "Freeform".
- **SpriteShapeType** (scene shape-node picker, PI:3625): rect "Rectangle", circle "Circle", ellipse "Ellipse", path "Path". *(Corrected at Review — real cases are rect/circle/ellipse/path, SceneSpec.swift:605. "Ellipse" does not become "Oval": the sprite layer distinguishes circle from ellipse, and reusing the classic part word would create a false cognate.)*
- **ChartType**: hand-written Title Case per case (no `.capitalized`).
- **SceneScaleMode**: hand-written Title Case per case.

### 2.3 Per-control row labels — the complete table

Format: **Section header** (via `sectionHeading`) → rows with exact strings. Unchanged rows are listed to make the table the single conformance source. "(ro)" = read-only `propertyRow(_:value:)`.

**Common — every part** (PI:932-973):
- **Identity**: Name · Type (ro, displayName)
- **Position & Size** (renamed from "Position" — it contains size; matches multi-select): X · Y · Width · Height
- **State**: Visible · Enabled
- **Help**: help editor + caption (unchanged)

**Button** (PI:976): Style (display names) · Label (caption: "Shown on the button when Show Name is off.") · Show Name · Auto Hilite · **Hilite** *(new row, shown only when Style is Toggle, Check Box, or Radio; caption: "The checked / on state.")* · conditional **Popup Items** block (unchanged).

**Field** (PI:1004): Style (display names) · Lock Text · Don't Wrap · Rich Text · Wide Margins · **Events** header via `sectionHeading` (PI:1018) · Enter Key Event (+ existing caption) · **Contents** (was "Content") · *(new, only when Style = Search)*: **Prompt** · **Search While Typing** (caption: "When off, searching happens when Return is pressed.") — closes the "search style selectable but its props unexposed" gap.

**Shape** (PI:1053): **Style** (was "Shape") · Fill · Stroke · Stroke Width · Corner Radius · **Rotation** *(new — universal field honored by the shape renderer, Part.swift:26-36; numberField + "°")*.

**Web Page** (PI:1071): URL.

**Image** (PI:1079): Choose Image… · Invert on Click · Animated · Transparent Background · **Rotation** *(new, + "°")* · Filter · Intensity · size caption (ro).

**Video** (PI:1148): **Source** (was "URL/Path"; placeholder "File path or URL") · Choose Video… · *(new playback rows — closes A5/H7 at the panel level)*: **Autoplay** · **Loop** · **Volume** (slider 0–1, audio-node idiom PI:3659-3662) · **Play Rate** (numberField + "×"). Current time/duration remain script-only runtime state (documented).

**Chart** (PI:4286): Type (display names) · Title · Show Legend · Show Grid · **Interactive** (was "Interactable") · X Label · Y Label · spider block: Show Value Labels · Split Area · Circular Grid · Rings · **Grid Color / Axis Color / Label Color** · data points: Name · Value · **Min** · **Max** (were "Minimum"/"Maximum").

**Sprite Area** (PI:2013): Scene Name · Nodes (ro) · Size (ro) · **Setup Checklist / Physics / Controls / Debug / Nodes** headers all via `sectionHeading` (PI:2075, 2112, 2121, 2141, 2148) · Gravity (dx/dy — stays; the per-node boolean disambiguates, below) · Show FPS · Show Physics · Show Node Count · Paused · Transparent Background.

**Calendar** (PI:1164): **Date** (placeholder `yyyy-MM-dd`) · **Time** (placeholder `HH:mm:ss`) · Display Month (placeholder `yyyy-MM`) · Min Date · Max Date · Style.

**PDF** (PI:1187): **Source** (was "URL/Path") · Choose PDF… · Page · **Display Mode** (was "Mode") · **Auto-Scale to Fit** (capitalization fix).

**Map** (PI:1238): Center Lat · Center Lon · **Span** (+ "°", was "Span (deg)") · Location (+ caption) · Type · **Annotations** (was "Annotations JSON"; format caption stays) · **Show User Location** *(new row — mapShowsUserLocation, Part.swift:215; caption: "Shows the system location dot in Browse mode. macOS asks for location permission the first time.")*.

**Color Well** (PI:1276): Color · Interactive (kept — §1.5 term of art, matches HypeTalk key).

**Stepper / Slider** (PI:1285): header via `sectionHeading("Stepper"/"Slider")` (fixes the raw `.subheadline` Text, PI:1287) · Value · Min · Max · Step (stepper only).

**Segmented Control** (PI:1302): **Segments** (was "Segments (pipe-separated)"; caption: "Separate segments with | — e.g. Day|Week|Month.") · **Selected Segment** (was "Selected Index"; caption: "0 = first segment.").

**Audio Recorder** (PI:1506): Recording · Playing · Save Recordings in Stack · Format · Output Path · **Stored Audio** (ro, no colon) · **Duration** (ro, no colon, value "2.4 s").

**Synth Music** (musicPlayer/pianoKeyboard/stepSequencer/musicMixer, PI:1551): Pattern · Instrument · Keys · Tempo (BPM idiom — the reference pattern) · toggles become **Show Control Type / Show Pattern Name / Show Instrument Popup / Show Tempo** (fixes the Pattern/Tempo double-labeling PI:1554/1577 and 1596/1579; the "Show on Keyboard/Sequencer" sub-caption is removed as redundant) · Loop · Volume · *(new, sequencer/mixer only)*: **Tracks** (ro, parsed count from `musicTrackData`; caption: "Edit tracks on the control in Browse mode. Scripts: the trackData of this part.") — a real track editor is a **documented deferral** (§7); the control itself is the editor.

**Apple Music** (appleMusicBrowser — section header renamed from "MusicKit Search"; MusicKit is framework-speak, Apple Music is the user's word; PI:1617): Search · Search Scope · **Type** (was "Music Type") · Authorize/Search buttons · Result · Selected ID · Title · **Artist** (was "Artist / Singer"; and `appleMusicDisplayName(.artist)` at PI:1797 returns **"Artist"**, not "Singer" — one concept, one word, correct for bands and composers) · Album · Artwork URL · **Position** (+ "s") · **Duration** (+ "s") · Play/Seek/Stop · captions (with "MusicKit Search" in prose at PI:1587 becoming "Apple Music search").

**Music Queue** (PI:1811): Legacy Music Queue · Queue Data · caption (unchanged).

**3D Scene** (PI:1310): From Repository · Generate from prompt… · Object Path · **Resolved Path** (ro, was "Resolved") · Allow Camera Control · **Auto Lighting** (was "Default Lighting"; matches `scene3DAutoLighting` semantics and the Auto-X rule) · Background · **Anti-Aliasing** (capitalization).

**Progress View** (PI:1823): Label · Circular Spinner · Indeterminate · Value · **Max** (was "Total") · Tint · Decimals (+ existing captions, updated to say Max).

**Gauge** (PI:1857): Label · Value · Min · Max · Style (display names; the picker's abbreviated entries "Acc. Circular Cap." may stay — genuine space constraint in a menu picker, documented exception) · Tint · Min Label · Max Label · Decimals.

**Divider** (PI:1906): Orientation · **Thickness** (+ "pt") · Color.

**Text Formatting** (buttons/fields, PI:4189): Font · Size · Align · **Text Color** (was "Color") · Style toggles.

**Not exposed, by decision** (each documented in the guide, §4): `htmlContent` (dormant/unreachable — no inspector row, no new script surface; listed as legacy), `iconId` (needs an icon-picker feature; deferral — pairs with H8 fix), `musicTrackData` raw editor (deferral above), `pathData`, `urlSourceFieldId`, `groupId`, `sortKey`, `family`, `menuItems`/`menuTitle` (editor-internal or dead vocabulary).

### 2.4 Multi-select panels — same words as single-select

- Part multi (PI:280-474): section "BEHAVIOR" → **State** (same as single); "Stroke W"/"Corner R" (PI:375) → **Stroke Width** and **Corner Radius** as two stacked rows (the paired layout genuinely cannot fit the full words; stacking, not abbreviating, is the resolution); Text Formatting "Color" → **Text Color**.
- Node multi (PI:3268-3337): "W"/"H" → **Width**/**Height**; "Rot" → **Rotation**; "zPos" → **Z** (matching the single panel's established "Z", PI:3505); "xScale"/"yScale" → **Scale X**/**Scale Y** (no raw Swift identifiers as labels); "Hidden" → **Visible** (inverted binding); "Font Color" → **Text Color**; "Size" (fontSize) stays "Size" inside the label-only block.
- Node single (PI:3494+): hand-rolled 9pt headers ("POSITION", "SPRITE", "LABEL", "SHAPE", "AUDIO", "EMITTER", "VIDEO", "PHYSICS", "CROP", "EFFECT", "LIGHT") all route through `sectionHeading()`; "Hidden" → **Visible**; label node "Color" → **Text Color**; shape node "Type" → **Style**; physics "Gravity" toggle → **Affected by Gravity** and "Rotation" toggle → **Allow Rotation** (resolves both same-panel collisions: scene Gravity vector vs node boolean, and rotation angle vs allowsRotation).

---

## 3. HypeTalk + AI naming rules

The AI surface uses the HypeTalk canonical names, lowercased, with identical alias sets and identical dispatch — one shared registry drives both (see §3.8). Findings H1–H10 and A1–A6 resolve as follows.

### 3.1 Polymorphic dispatch for `value` / `min` / `max` / `step` (fixes H3)

`min`/`max`/`step` dispatch per partType exactly as `value` already does (IP:5668-5677):

| partType | value | min | max | step |
|---|---|---|---|---|
| stepper, slider | controlValue | controlMin | controlMax | controlStep |
| gauge | gaugeValue (via `setGaugeValue`) | gaugeMin | gaugeMax | error |
| progressView | progressValue (via `setProgressValue`) | GET → "0"; SET → accept only 0, else error "progress always starts at 0 — set the max instead" | progressTotal | error |
| segmented | index (existing) | error | error | error |
| toggle (button style) | bool (existing) | error | error | error |
| field | textContent (existing) | error | error | error |
| calendar | — | minDate | maxDate | error |
| all others | existing behavior | error | error | error |

The old silent fallback to `controlMin/Max/Step` on every type disappears; a nonsense target now errors (consistent with §3.7).

### 3.2 `size` (fixes H2, A6)

`the size of <part>` is the geometry pair on **both** GET and SET: GET returns `"width,height"` (unchanged); SET now accepts `"width,height"` and writes width/height. The old SET-writes-`textSize` behavior is removed on both HypeTalk and AI surfaces; a non-pair argument errors with: `size expects "width,height" — use textSize to set the text size.` Text size keeps its classic name **`textSize`** (classic HyperTalk precedent: `the textSize of` is the HyperCard property). This is the one deliberate breaking change; it converts a silent wrong-field write into an explicit error with the correct name in the message.

### 3.3 Bare-alias ownership — dispatch by partType (fixes H7, A6)

| Bare name | video | music types | gauge | progressView | field (search style) | others |
|---|---|---|---|---|---|---|
| `loop` | videoLoop | musicLoop (unchanged) | — | — | — | error |
| `volume` | videoVolume | musicVolume (unchanged) | — | — | — | error |
| `autoplay` | videoAutoplay | — | — | — | — | error |
| `playRate` (+`rate`) | videoPlayRate | — | — | — | — | error |
| `currentTime` | videoCurrentTime (GET/SET) | — | — | — | — | error |
| `duration` | videoDuration (GET only; SET errors — derived) | musicDuration / audioDuration (existing dispatch) | — | — | — | audioDuration (recorder) |
| `tint` | — | — | gaugeTint | progressTint | — | error |
| `prompt` | — | — | — | — | searchPrompt | error |
| `total` | — | — | — | progressTotal (compat alias of `max`) | — | error |

Long names (`videoLoop`, `musicVolume`, …) always work on their own type regardless of the bare-alias table. The classic movie-window shim (IP:7994-8045) remains but is no longer the only path.

### 3.4 Alias symmetry law (fixes H6)

For every property, the GET alias set and SET alias set are **identical**, except properties declared read-only (`duration` of video, `pageCount`, `audioSize`, `resolved` scene path, `type` — §3.6), whose SET produces the read-only error, never a variable write. Concretely closes: `items` (SET gains it for popupItems/menuItems), bare `tint` (GET gains it), `modelAsset`/`assetName` (GET gains them for scene3D).

### 3.5 Individual bug resolutions

- **H1** — GET `style` dispatches button → buttonStyle, field → fieldStyle, **shape → shapeType**, mirroring the SET branch (IP:7469-7479). Aliases `shape`/`shapeType` remain for shapes.
- **H4** — `marked` targeting a *part* errors: `"marked" is a card property — try the marked of this card.` Card-target behavior unchanged. (Classic HyperTalk fidelity: `marked` belongs to cards.)
- **H5** — stack SET switch accepts the spaced form `user level` (parity with GET IP:5332 and the global form IP:976).
- **H8** — GET `icon` returns `""` when no icon (was `"0"`), matching the app-wide empty-string sentinel convention. SET accepts `""` or `"0"` to clear (the `0` kept as a nod to classic numbered icons).
- **H9** — `background` gains the `short/long/abbreviated name` variants that stack/card/part already support (IP:5488-5507).
- **H-gap** — add read-only **`the type of <part>`** returning the partType rawValue (stable machine form; scripts can branch on it; the inspector Type row shows the display name of the same fact).
- **H-noop stubs** — the 11 classic field props + `scroll` remain *explicit* accepted no-ops (imported classic stacks must not error); they are exempt from §3.7 by declaration, not by fallthrough.
- **`pageCount`** — remains read-only "0" at model layer; docs must say so.

### 3.6 Read/write declarations

Every property in the registry is declared `get`, `set`, or `get+set`. Read-only: `type`, video/audio `duration`, `pageCount`, `audioSize`, scene3D resolved path, music source metadata snapshots where live playback owns them. Write-only: none.

### 3.7 Kill the typo-swallowers (fixes H10, A2)

- **SET of an unrecognized property on an object target is a runtime error**, never a script-variable write (IP:7969-7971 removed). Classic precedent: classic HyperTalk errored ("Never heard of that property"); `set` was never variable assignment — that was `put … into`. Error copy: `no such property "gaugvalue" for button "OK"` — with a nearest-match hint (`did you mean "gaugeValue"?`) when an edit-distance-1..2 candidate exists. Plain `set <var> to <expr>` with no `of <object>` clause is untouched.
- **Type-scoped keys error on the wrong partType** (AI + HypeTalk): setting `gaugeValue` on a button errors instead of mutating a never-rendered field.
- **`value`/`on` on parts with no value concept error** instead of silently writing `controlValue` (A2).
- **GET posture (documented decision, accepted at Review):** strictness is SET-side. GET errors only on declared dispatch-table error cells (bare polymorphic names on unlisted types; `marked` on a part) and on nothing else: GET of a long type-prefixed name remains a permissive stored-field read, and GET of a fully unknown name keeps returning `""`. Rationale: reads cannot corrupt, and speculative `the <x> of` reads in existing stacks must not start throwing. The guide must state this read posture explicitly (§4).

### 3.8 AI surface specifics

- **A1** — `list_all_properties` is generated from the same registry and is verifiably complete: it gains `musicSourceAlbum`, `musicArtworkURL`, `musicQueueData`, `musicSearchTerm`, `musicSearchScope`, `mapShowsUserLocation`, `scene3DSourceURL`, and PDF asset info; `htmlContent` and the dead editor-internal fields are listed under an explicit "legacy / not scriptable" note rather than omitted silently. Secure-field masking behavior is preserved verbatim.
- **A3** — one permissive `boolArgument` parser everywhere on the AI surface (accepts true/false/yes/no/y/n/1/0/on/off, case-insensitive). HypeTalk keeps its own boolean expression semantics.
- **A4** — the duplicate dead chart cases in the main switch are deleted; `applyChartProperty` is the single chart path; its bare `title`/`interactive` aliases become the documented canonical behavior.
- **A5 closures** — new curated get/set: video playback family (§3.3), `popupItems` (newline list, matching the inspector editor contract), field flags (`dontWrap`, `wideMargins`, `richText`, `enterKeyEnabled` — classic names), `showsUserLocation`, `invertOnClick`, `animated`. `pdfAssetRef` binding tool: **deferred**. `htmlContent`: **no new surface** (dormant; legacy-documented — if the Architect finds a live renderer consuming it, escalate back to Design).
- **SEC** — masking asymmetry between `hype_get_object`/`hype_replace_part` and the curated tools is flagged for the Security (plan) phase; Design's requirement is only that *whatever* policy Security picks is uniform and documented.

---

## 4. Docs surface

`Sources/HypeCore/AI/HypeTalkGuide.swift` and `HypeTalk-LLM-Context.md` are regenerated (or hand-reconciled) **from the registry** so both agree with the real dispatch and with each other. The guide documents, per property: canonical name, aliases, applicable part types, mutability, value format, and sentinels ("" = auto/none). The LLM-Context doc is a strict subset of the guide (no contradictions — fixes the current fontColor/textContent/url/helpText disagreement, A1). Breaking-change notes for `size` (§3.2) and strict-SET (§3.7) appear in both.

**Acceptance criterion (the Tester's conformance test):** a test walks every property name in both docs and asserts the GET dispatch resolves it on at least one declared part type; and walks every registry-canonical property and asserts it appears in the guide. Alias-symmetry and read-only declarations are asserted from the registry, not prose.

---

## 5. States

- **No selection / paint / multi / single** top-level states: unchanged.
- **Mixed values**: "Multiple" placeholder (existing) — new multi rows must use it.
- **Empty/none**: picker "— None —", read-only "(none)", caption "Empty = …" — the three existing sentinels only.
- **Disabled**: rows that cannot act are disabled with a reason available via `.help` (existing precedent: PI:1511, PI:1327).
- **Conditional**: style-scoped rows (Hilite, Search props, Popup Items, spider block) appear/disappear with the style picker — the existing popup-items pattern.
- **Error**: HypeTalk/AI error strings per §3.7 — specific, name-bearing, suggestion-bearing.

## 6. Accessibility requirements

- Every `Picker("", …).labelsHidden()` / `TextField` with a detached `Text` label gains `.accessibilityLabel` with the row's canonical label (spider fields at PI:4455/4496 are the in-repo precedent). In scope since every row is being touched.
- Color rows: the swatch alone never carries meaning — the hex field (text) is always present (guaranteed by `colorPropertyRow`).
- Unit texts are appended to the accessibility label ("Span, degrees").
- No color-only signals introduced; no motion introduced; contrast inherited from the themed panel (PI:233).

## 7. Documented deferrals

1. Icon picker UI (`iconId`) — needs an icon-asset browser; H8 sentinel fix ships now.
2. Sequencer/mixer track editor (`musicTrackData`) — the control is the editor; inspector shows the read-only Tracks count now.
3. `pdfAssetRef` AI binding tool (scene3D parity).
4. Secure-field masking for the MCP object tools — **ruled at Security (plan): tracked as a required immediate follow-up change (Security-flagged HIGH)**: mask `.secure` field `textContent` at `getObject`/`fullDocumentResource`/`hype_get_stack_document`; rule explicitly on `replacePart` validation. Not an open-ended residual; Security re-reviews it when it lands.
5. Residual typo-swallowers — the target-not-found SET fallback (Interpreter.swift:1603-1605 writes a script variable when the *object* doesn't resolve) and unknown-name GET `""` (§3.7 note) — recommended follow-up change; out of this change's scope by decision.
6. Editor/runtime empty-button-label divergence observed at Review: the editor draws a blank face (ButtonRenderer.swift:163), the exported runtime substitutes the literal "Button" (TargetRuntimeControlViews.swift:962) — a WYSIWYG break to reconcile in an export-fidelity follow-up.

---

## 8. Acceptance criteria (Architect builds to these; Tester verifies these)

1. **Round-trip law**: for every registry property P declared `get+set` on partType T, `set the P of <T-part> to v` followed by `get the P` returns v (modulo documented clamping/normalization). Property-tested across the registry, both HypeTalk and AI surfaces.
2. **Alias symmetry law**: for every property, GET alias set == SET alias set, except declared read-only properties whose SET errors. Asserted mechanically from the registry.
3. **Dispatch table conformance**: `min`/`max`/`step`/`value`/`loop`/`volume`/`autoplay`/`tint`/`prompt`/`total`/`duration` resolve per §3.1/§3.3 for every partType listed; unlisted types error. One test per cell.
4. **`size` pair law**: GET returns "w,h"; SET of "w,h" round-trips; SET of a single number errors with copy naming `textSize`; `textSize` unaffected.
5. **Strict-SET law**: SET of an unknown property on an object target errors (no variable is created); error copy contains the property name and object type; the 11 classic no-op stubs still no-op without error.
6. **Wrong-type write law**: every type-scoped key errors on a non-applicable partType on both surfaces.
7. **H-bug regression tests**: H1 (shape `style` GET == shapeType), H4 (part-target `marked` errors; card-target unchanged), H5 (`set the user level of this stack` spaced form works), H8 (`the icon of` a button with no icon `is empty` is true), H9 (background name variants).
8. **Boolean parser**: one shared permissive parser on the AI surface; fuzz test over token case/whitespace variants; `"1"` sets `visible` true.
9. **Chart single-path**: dead switch cases removed; every chart key reachable only via `applyChartProperty`; `title`/`interactive` work.
10. **A5 closure tests**: `popupItems`, video playback family, field flags, `showsUserLocation`, `invertOnClick`, `animated` get/set on both surfaces.
11. **`list_all_properties` completeness**: a test diffs its emitted key set against the registry — zero missing, zero phantom; secure masking still applied.
12. **Docs conformance**: §4's two-direction test passes; guide and LLM-Context agree.
13. **PartType display names**: exhaustive switch (no `default`); a test asserts every case's display name matches the §2.1 table exactly; headline (PI:74) and Type row (PI:936) render through it.
14. **No raw rawValue in UI**: no `Text(….rawValue)` and no `.rawValue.capitalized` remains in `PropertyInspector.swift` for PartType, ButtonStyle, FieldStyle, ShapeType, SpriteShapeType, ChartType, SceneScaleMode.
15. **Label-spec conformance**: the exact strings of §2.3/§2.4 exist at their sites. Includes: "Contents", "Selected Segment", "Max" (progress), "Show Pattern Name", "Artist" (both row and picker case), "Interactive" (chart), "Text Color" (all four sites), "Affected by Gravity", "Allow Rotation", "Visible" (node panels), "Auto Lighting", "Display Mode", "Style" (shape part + shape node).
16. **No trailing colons; Title Case**: no rendered row label ends with ":"; changed labels follow §1.7.
17. **Section-heading rule**: zero hand-rolled section headers remain in `PropertyInspector.swift`.
18. **Units rule**: no rendered label contains a parenthesized unit; the tempo-style unit idiom is used at the §1.6 sites; date rows use placeholders.
19. **New rows render**: Rotation (shape+image), Hilite (conditional), video Autoplay/Loop/Volume/Play Rate, Show User Location, Prompt + Search While Typing (conditional), Tracks (ro) — each visible on a part of the right type/style and absent otherwise.
20. **Accessibility**: every labels-hidden control in touched rows has an `accessibilityLabel` equal to its canonical label.
21. **No regression to untouched design language**: theme picker, constraints section, script section, alignment tools unchanged (visual spot-check at Sign-off).

**Sign-off note:** items 13–21 include visual verification: one part of each of the 26 live part types (headline + Type row), the button style picker open, a segmented part, a progress part, a search-style field, a video part, a map part, the node detail + node multi panels, and the part multi panel.

---

Key files for the Architect: `Sources/Hype/Views/PropertyInspector.swift`, `Sources/HypeCore/Script/Interpreter.swift`, `Sources/HypeCore/AI/HypeToolExecutor.swift`, `Sources/HypeCore/AI/HypeTools.swift`, `Sources/HypeCore/AI/HypeTalkGuide.swift`, `Sources/HypeCore/Models/Part.swift` (read-only), `Sources/HypeCore/Models/HypeStack.swift` (displayName extensions only — no stored-key changes).

---

## Revision log

**2026-07-17 — Design Review/Revision (Designer), reviewing the Architect's design.md:**

1. **§2.2 SpriteShapeType corrected** (Architect's erratum accepted): real cases are `rect, circle, ellipse, path` (SceneSpec.swift:605), not the ShapeType list. Display names: Rectangle / Circle / Ellipse / Path. Split into its own bullet; "Ellipse" deliberately not renamed "Oval" (circle vs ellipse are distinct sprite cases — classic word would be a false cognate).
2. **Button Label caption corrected**: the original caption "When empty, the Name is shown." was false on every button path. Ground truth: ButtonRenderer.swift:162/206/247/355/394/445 draw `showName ? name : textContent` (empty → nothing drawn); the exported runtime (TargetRuntimeControlViews.swift:960-963) falls back to the literal "Button", never the Name. The mock's original citation (TargetRuntimeControlViews.swift:1169) is the tvOS *field* view — its empty→Name fallback was misattributed to buttons. New caption: "Shown on the button when Show Name is off." §1.3, §2.3, and the grounding line updated.
3. **§3.7 GET-leniency decision recorded**: the Architect's Decision 3 (SET strict; GET lenient outside declared error cells; unknown GET stays `""`) is accepted as honoring the mock — H10/A2 were write defects. Condition: the guide states the read posture.
4. **§7 deferrals extended**: residual typo-swallowers (target-not-found SET fallback, unknown-GET `""`) recorded as deferral 5; editor/runtime empty-button-label divergence recorded as deferral 6.
