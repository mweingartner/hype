# Control-Property Consistency Audit — Synthesis (working)

Surfaces: (M) Part model · (H) HypeTalk get/set · (A) AI tools · (I) Inspector labels · (D) AI-facing docs (HypeTalkGuide.swift + HypeTalk-LLM-Context.md)

Status: M done, A done, H pending, I pending. D partially done (main session).

## Confirmed cross-surface findings (from M + A + D so far)

### SEC — security-posture asymmetry (highest severity)
- `hype_get_object` / `hype_replace_part` (MCP control tools) bypass the curated
  property surface: full Part JSON, **no secure-field masking** — a
  `fieldStyle == .secure` field's `textContent` returns plaintext, while
  `get_part_property`/`list_all_properties` deliberately mask it
  (HypeToolExecutor.swift:3779-3782, 6273-6279; HypeMCPDocumentBackend.swift:494-519,576-605,679-685).
  Mitigant: runs over HypeDebugServer local-socket debug boundary. Still an
  inconsistency between two tool families in the same allTools list.

### A1 — no single source of truth for the AI property vocabulary
- Tool descriptions (HypeTools.swift:972-1004,1213-1229) document only a curated
  subset of what the executor switch actually supports.
- `list_all_properties` (formatAllProperties, 6235-6465) CLAIMS "EVERY property"
  but omits: musicSourceAlbum, musicArtworkURL, musicQueueData, musicSearchTerm,
  musicSearchScope, mapShowsUserLocation, scene3DSourceURL, pdf asset info.
- HypeTalkGuide.swift:170 documents ~30 part properties of 146; HypeTalk-LLM-Context.md:98
  documents even fewer and DISAGREES with the guide (omits fontColor, textContent,
  url, helpText) despite "must update both together" comment.

### A2 — silent no-op / wrong-field writes
- `value`/`on` on a non-form-control silently writes `controlValue` (no render
  effect on button/shape/webpage) — masks typos as success (2110-2126).
- Any type-specific key (e.g. gaugevalue) accepted on ANY part type, mutating a
  field the control never renders. Setter/getter asymmetric after type drift.

### A3 — boolean parsing inconsistent
- Strict `== "true"` on most fields (visible/enabled/hilite/…) vs permissive
  boolArgument (yes/y/1/on) on audioEmbedInStack, music*, chart booleans.
  AI emitting "1" for visible → silently false.

### A4 — chart property dead code + drift
- applyChartProperty (6568-6661) intercepts .chart first (2059-3062); the
  duplicate chart cases in the main switch (2417-2442, 3941-3960) are dead code,
  and diverge: `title`/`interactive` bare aliases exist only in applyChartProperty.

### A5 — Part fields with NO AI path (settable nowhere in curated surface)
- Video playback: videoCurrentTime/videoDuration/videoPlayRate/videoAutoplay/
  videoLoop/videoVolume/videoAssetRef — only videoURL reachable. (SpriteKit
  node namesakes ARE settable — name collision across models.)
- popupItems (popup button item list — NO AI write path at all)
- htmlContent (completely unreachable, not even list_all_properties)
- dontWrap/wideMargins/richText/enterKeyEnabled (field flags: bulk-read only)
- mapShowsUserLocation (no get/set case despite doc comment saying HypeTalk-settable)
- invertOnClick/animated (image): read-only in bulk dumps
- pdfAssetRef binding (no AI tool, unlike scene3D which has full binding)
- pathData, urlSourceFieldId, iconId, groupId, sortKey, family (editor/dead)

### A6 — key overloads
- `size` = textSize (set_part_property) vs scene size (set_scene_property) vs
  text_size (create_field helper).
- `duration` (read) = audioDuration OR musicDuration by partType; no write case.
- Bare aliases (filter/tint/prompt/orientation/thickness/volume/loop) shared
  across unrelated controls, disambiguated only by partType.

### M1 — model naming drift (ranked, from model agent)
1. Color suffixes: *Color / *Tint / *Background / *Hex (fontColor, fillColor,
   strokeColor, dividerColor | progressTint, gaugeTint | scene3DBackground |
   colorWellHex). All untyped String; only ChartConfig.normalizedHex validates.
2. Boolean prefixes: bare / is* / show* / Shows* / allows* / auto* / dontWrap.
3. gaugeDecimals vs progressDecimals: same name+type+default, OPPOSITE semantics
   at 0 (gauge: full precision; progress: integer steps). Part.swift:854-887.
4. Range: Min/Max vs progressTotal (no floor) vs chart minimumValue/maximumValue.
5. controlValue polymorphism: slider pos | legacy-toggle bool | segment index.
6. music* prefix spans AudioKit pattern controls AND MusicKit catalog controls —
   two bounded contexts, one prefix; inspector already splits sections.
7. Dead vocabulary: family, menuItems, menuTitle (unprefixed, inert).
8. scene3DURL vs scene3DSourceURL — resolved-vs-authored distinction prose-only.

### M2 — type inconsistencies
- Colors: 10+ String hex fields, no shared type; ColorRef exists in Theme/ unused here.
- Dates as String (deliberate/portab.) but breaks Min/Max typing symmetry.
- JSON blobs: chartData/sceneSpec (decoded to structs) vs mapAnnotationsJSON/
  musicTrackData/musicQueueData (raw JSONSerialization dict access).
- Legacy toggle: controlValue(0/1) → hilite(Bool) migration duality.

## H — HypeTalk findings (Interpreter.swift; GET switch ~5562-5951, SET switch ~7411-7972)

### H-BUGS (defects, not just drift)
- **H1 `style` GET broken for shapes**: GET is `.button ? buttonStyle : fieldStyle`
  (IP:5608-5609) → a shape returns fieldStyle garbage ("rectangle" default);
  SET branches correctly button/field/shape (IP:7469-7479). GET/SET asymmetric.
- **H2 `size` not a round-trip**: GET "size" → "width,height" pair (IP:5884-5885);
  SET "size" → textSize single number (IP:7441-7442). Sharpest asymmetry found.
- **H3 `min`/`max`/`step` don't polymorph like `value` does**: hard-wired to
  controlMin/Max/Step for ALL types (IP:5680-5682, 7712-7717). `set the max of
  gauge "T" to 100` silently writes unused controlMax, not gaugeMax. Progress
  floor/ceiling unreachable via min/max entirely.
- **H4 `marked` of a part reads/writes the CARD's marked** (IP:5869-5873,
  7536-7539) — part-name ignored.
- **H5 stack `user level` (with space) SET no-ops**: GET accepts "user level"
  (IP:5332); stack SET switch only "userlevel"/"user_level" (IP:1537). Global
  form works (IP:976). Object-ref path bug.
- **H6 alias asymmetries (GET set ≠ SET set)**: menuitems GET accepts "items",
  SET doesn't; gaugetint SET accepts bare "tint", GET doesn't; scene3D SET
  accepts modelasset/assetname, GET only object/model.
- **H7 video part playback unreachable**: bare loop/volume claimed by music
  (musicLoop/musicVolume, IP:5719/5721, 7750/7752); videoLoop/videoAutoplay/
  videoVolume reachable ONLY via classic movie-window shim keyed by window
  name (IP:7994-8045). Node layer repeats collision (audio wins bare names).
- **H8 `icon` empty sentinel is "0"** not empty (IP:5883) — `is empty` never true.
- **H9 background lacks short/long/abbrev name variants** (IP:5488-5507) that
  stack/card/part all support.
- **H10 SET fallthrough**: any unrecognized property name silently becomes a
  script VARIABLE (env.setVariable, IP:7969-7971) — typos vanish. (Mirrors AI
  surface's value/on fallthrough problem: error-masking by design.)

### H-gaps (no getter nor setter): sortKey, groupId, pathData, urlSourceFieldId,
imageData, pdfAssetRef, videoAssetRef (window-shim only), audioData (count only),
cardId/backgroundId (no reparent), partType (no `the type of X`!), scene3DSourceURL/
scene3DAssetRef (opaque via object/model), raw sceneSpec.
### H-noop stubs: scroll/scrollpos + 11 classic HyperCard field props (sharedText,
sharedHilite, showLines, showPict, fixedLineHeight, multipleLines, dontSearch,
autoSelect, autoTab, cantDelete, cantModify) — GET hardcoded, SET explicit no-op.
~35 global env props GET-only hardcoded; SET degrades to unrelated script var.
### H-consistency: HypeTalk names mostly match AI keys 1:1 (same alias families) —
GOOD baseline. pagecount hardcoded "0" (IP:5646-5651). progressTotal breaks
Min/Max symmetry at language level too.

## I — Inspector findings (PropertyInspector.swift, 5675 lines)

### I-BUGS (visibly broken UI)
- **I1 `.capitalized` on camelCase PartType rawValues** → "Colorwell", "Musicplayer",
  "Pianokeyboard", "Stepsequencer", "Musicmixer", "Applemusicbrowser", "Musicqueue",
  "Progressview", "Audiorecorder", "Scene3d", "Spritearea", "Searchfield", "Pdf"
  shown in the Type row + headline (PI:74, 936). Section headers hand-written
  correctly — same part shows two different type spellings.
- **I2 raw enum rawValue in pickers**: buttonStyle "checkBox" (PI:981), fieldStyle
  "scrolling" (1009), shapeType "roundRect" (1058, 3625). Other pickers hand-write
  Title Case.

### I-language drift (same concept, different words)
- Color: "Fill"/"Stroke"/"Color"/"Background"/"Tint"/"Font Color"/"Particle Color"/
  bare "Grid"/"Axis"/"Labels" (chart colors) — 9 spellings.
- controlValue: "Value" (stepper/slider PI:1289) vs "Selected Index" (segmented 1306).
- Range: "Min"/"Max" vs "Minimum"/"Maximum" (spider 4465) vs "Total" (progress 1831).
- textContent: "Label" (button 984) vs "Content" (field 1043) — same field.
- Enum-variant word: "Style"/"Mode"/"Type"/"Format" + "Shape" vs "Type" for shapeType
  (1056 vs 3623). "Style" also reused for bold/italic row.
- "Rotation" ×2 in same node panel: angle numberField (3504) + allowsRotation
  physics Toggle (3797).
- "Gravity" ×2 in same section: scene dx/dy vector (2113) + per-node boolean (3795).
- "Pattern"/"Tempo" each label BOTH the value row and its show-toggle (1554/1577,
  1596/1579). musicShowInstrument → "Instrument Popup" breaks Show-X pattern.
- "Artist / Singer" hedge (1647) vs picker rendering .artist as "Singer" (1795).
- Polarity: "Interactive" (on=usable) vs "Lock Text" (on=not-editable).

### I-style drift
- stepper/slider header raw Text not sectionHeading() (1287); sprite-node headers
  hand-rolled size-9 uppercase (3569+) vs helper's size-10.
- Trailing colons on exactly 2 labels: "Stored Audio:" (1538), "Duration:" (1544).
- Multi vs single abbreviations: "Stroke W"/"Corner R" (375) vs full names (1065);
  "W"/"H"/"Rot"/"zPos" (3274-3289) vs "Width"/"Height"/"Rotation"/"Z" (3500-3505);
  "Font Color" (3335) vs "Color" (3616).
- Raw Swift identifiers as labels: "xScale"/"yScale" (3285-3286).
- Units: in label "(deg)"/"(pts)"/"(yyyy-MM-dd)"/"Seconds" vs caption vs formatted
  value — 3 strategies.

### I-missing from panel
- **rotation** (universal field, honored by shape/image renderers — NO inspector row!)
- hilite (actual checked/on state — only autoHilite shown)
- iconId (no icon picker anywhere in app)
- htmlContent; video playback ×5 (autoplay/loop/volume/playRate/currentTime — node
  editor MORE complete than the part's own section); mapShowsUserLocation;
  searchText/searchPrompt/searchSendsImmediately (search style selectable but its
  3 props unexposed!); musicTrackData (sequencer/mixer get generic Synth panel).

## SYNTHESIS COMPLETE — all four surfaces mapped.

## Remediation shape (draft, refine after H+I)
- R1: Single property registry as source of truth (name, aliases, type, applicable
  partTypes, validation, mutability, secure-masking) → generate/drive: executor
  switch, list_all_properties, tool descriptions, HypeTalkGuide, LLM-Context doc.
  (Big; maybe phased. At minimum: one audit test asserting the surfaces agree.)
- R2: Close curated-surface gaps (video playback set/get, popupItems, field flags,
  mapShowsUserLocation, htmlContent policy decision).
- R3: Boolean parsing: one permissive boolArgument everywhere.
- R4: Chart: delete dead duplicate cases; single applyChartProperty path.
- R5: Type-checked property writes: warn/error when key not applicable to partType.
- R6: Secure-field masking for hype_get_object/hype_replace_part (or explicit
  policy doc that debug boundary is exempt).
- R7: Model renames w/ Codable migration aliases (color suffix, progressTotal→Max?,
  gauge/progress decimals contract) — HIGH RISK, decide scope with user.
- R8: Inspector label harmonization (pending I report).
- R9: Docs: regenerate HypeTalkGuide property lists + LLM-Context from registry;
  fix the two files' disagreement.
