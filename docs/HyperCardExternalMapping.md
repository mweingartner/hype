# HyperCard XCMD/XFCN Mapping

This document catalogs how Hype maps classic HyperCard external commands
(`XCMD`) and external functions (`XFCN`) during import and runtime execution.
It is a working compatibility map, not a claim of binary compatibility.

Hype never loads or executes original 68K/PPC external resources. Imported
resources are inventoried as legacy metadata, and script calls route through
`HyperCardExternalRegistry`. Externals not represented in the registry degrade
at runtime by setting `the result` to a `Can't Load External...` diagnostic.

## Runtime Behavior

| Area | Current behavior | Notes |
| --- | --- | --- |
| Resource discovery | Resource forks are parsed for `XCMD` and `XFCN` resources. | Resource names, IDs, byte counts, and registry status are included in the import report. |
| Native code execution | Not supported by design. | Classic external code is treated as untrusted data. |
| XCMD syntax | Unknown command identifiers with arguments can parse as `Statement.externalCommand`. | Example: `SetCursor "watch"`. |
| XFCN syntax | Function-call syntax falls through to the external registry after built-in HypeTalk functions. | Example: `put HypeVersion() into field "status"`. |
| Arguments | Arguments are evaluated as HypeTalk values before dispatch. | The registry currently treats these as string-compatible `Value`s. |
| Return value | XFCNs return `value`; XCMDs can update `it`. | Both can update `the result`. |
| Document mutation | Registry handlers may return a modified `HypeDocument`. | Intended for native Swift emulators only. |
| Runtime globals | Registry handlers may return runtime-only globals. | Used for compatibility state that should not become durable document schema. |
| Visual-effect intent | Registry handlers may return visual-effect metadata. | Used by transition-oriented externals such as Myst's `HTVisual`. |
| Pass message | Registry handlers may request `pass` behavior. | No default entry uses this yet. |
| Unknown external | Execution continues and `the result` receives a diagnostic. | This preserves stack execution where possible. |

## Status Legend

| Status | Meaning |
| --- | --- |
| Emulated | Implemented in Swift through `HyperCardExternalRegistry`. |
| Known unsupported | The name is recognized, but no emulator exists yet. |
| Planned | Reasonable candidate for a Swift/Hype-native replacement. |
| Research needed | Behavior, security model, or common legacy usage must be studied before implementation. |
| Unsupported by design | Native-code execution or unsafe system bridging will not be implemented directly. |

## XCMD Mapping

| XCMD name | Current support | Current behavior | Planned support or research needs |
| --- | --- | --- | --- |
| `SetCursor` | Emulated | Returns the requested cursor name in `the result`; does not currently change AppKit cursor state. | Planned: map common HyperCard cursor names to Hype cursor/UI state if scripts depend on visible cursor changes. |
| `Cursor` | Emulated | Alias of `SetCursor`; returns the requested cursor name in `the result`. | Same as `SetCursor`. |
| `playQT` | Emulated | Resolves a `.videoClip` asset by imported classic media metadata, creates a repository-backed video part on the current card, sets autoplay/loop/volume intent, and returns the resolved asset name. Audio-only QuickTime replacements such as `*-modern-audio.m4a` are marked as hidden 1x1 playback parts so classic ambient `playQT` calls do not create visible movie chrome. | Planned: exact classic movie rectangles and fade timing. |
| `PlayMovie` | Emulated | Alias of `playQT`. | Same as `playQT`. |
| `Movie` | Emulated | Resolves a `.videoClip` asset by imported classic media metadata and creates a repository-backed video part. When a classic point argument is present, the part is placed there and sized from imported asset dimensions. Common `set the ... of window ...` properties record runtime state; `loop`, `rate`, `movie`, `windowRect`/`rect`, `windowLoc`/`loc`, `windowName`, `audioLevel`, and `mute` update the compatibility video part. | Planned: callback timing, controller/badge flags, and exact QuickTime window semantics. |
| `closemoovs` | Emulated | Removes active compatibility video parts created by `playQT` on the current card and returns the removed count. | Planned: broaden if imported scripts reveal other QuickTime window lifecycle forms. |
| `closemovies` | Emulated | Alias of `closemoovs`. | Same as `closemoovs`. |
| `closeQT` | Emulated | Alias of `closemoovs`. | Same as `closemoovs`. |
| `HTLock` | Emulated | Normalizes lock/unlock-style arguments, records runtime-only compatibility state, sets `it` and `the result` to the normalized mode, and does not block drawing. | Planned: refine if Myst requires specific black-and-white or VBL lock behavior beyond script-visible state. |
| `HTVisual` | Emulated | Records transition arguments, maps the first argument to Hype's visual-effect result channel, converts the last positive numeric argument from ticks to seconds, and sets `it`/`the result` to the transition name. | Planned: map classic transition names and rect-scoped effects more precisely. |
| `DeCurse` | Emulated | Normalizes remove/override cursor modes, records runtime-only cursor resource/type/options state, and sets `it`/`the result` to the normalized mode. | Planned: connect imported cursor resources to visible Hype cursor state if gameplay evidence requires it. |
| `moveCursor` | Emulated | Parses a classic point/two-coordinate argument pair, records runtime-only cursor location intent, sets `hypercard.cursor.mode` to `move`, and returns `x,y` in `it`/`the result`. | Planned: connect to visible cursor movement only if a gameplay path requires it; current behavior intentionally avoids moving the macOS pointer. |
| `xWindowFrame` | Emulated | Records a runtime-only compatibility window named `frame`, returns `frame`, and makes `there is a window "frame"` evaluate true. | Planned: replace with real palette/window chrome only if later Myst frame handling needs visible UI. |
| `xAbout` | Emulated | Records that the imported about/install dialog external was invoked and returns empty without showing a modal dialog. | Planned: no visible UI unless imported scripts require a user-observable response. |
| `xMemory` | Emulated | Returns a deterministic positive memory value and records the query arguments in runtime-only compatibility state. | Planned: refine query-specific values if imported Myst conditionals require them. Also registered as an XFCN because Myst scripts call `xMemory(1)` in function style. |
| `xSetSoundVol` | Emulated | Parses and clamps a classic 0...255 volume, stores it in runtime-only compatibility state, updates active compatibility-created video parts, and returns the stored value. | Also registered as an XFCN because Myst scripts call `xSetSoundVol(origVol)` in function style. Future work can bind this state into non-video imported audio playback volume. |
| `SetMode` | Emulated | Records classic display mode/depth as runtime-only compatibility state and leaves `it`/`the result` empty. The imported Myst form `SetMode c,8` defaults an empty evaluated `c` token to color mode `c`. | Planned: bind to palette/color-depth rendering decisions if gameplay evidence requires more than script-visible state. |
| `HTAddPict` | Emulated | Resolves an imported image resource by classic name/metadata, creates a transparent compatibility image part on the current card, uses a classic destination rect when present, crops decoded image resources for `"srcRect", <rect>` arguments, composites recognized transfer modes into the current card paint layer when image pixels can be decoded, records the mode/composited-pixel count, and restores captured `clipboard` saves as compatibility image overlays after removing matching transient overlays. | PR 7a/7b/7c slice. Future work should target imported card/background paint layers more precisely and broaden compositing beyond the current byte-wise compatibility modes. |
| `HTChangePict` | Emulated | Resolves an imported image resource by classic name/metadata, replaces prior `HTChangePict` compatibility image parts on the current card, uses a classic destination rect when present, crops decoded image resources for `"srcRect", <rect>` arguments, and composites recognized transfer modes into the current card paint layer when image pixels can be decoded. | PR 7a/7b/7c slice. Future work should target imported card/background paint layers more precisely and broaden compositing beyond the current byte-wise compatibility modes. |
| `HTSavePict` | Emulated | Records classic save-rect, destination, transfer-mode, and argument intent. `clipboard` saves capture the current card paint-layer pixels into an internal clipboard image asset when a paint layer exists; `HTAddPict "", ..., "clipboard"` restores that capture as a compatibility overlay after removing matching transient overlays. | PR 7c slice. Future work should capture fully composited card/background pixels once imported paint-layer reconstruction is available. |
| `HTRemove` | Emulated | Clears compatibility-created PICT/icon/video parts and records the removed count. | PR 7d slice. Used by Myst stack teardown after HyperTint setup. |
| `HTUDefPal` | Emulated | Records the active user-defined palette resource ID as runtime-only compatibility state. When StackImport imported a palette-like resource (`clut`, `CTBL`, `actb`, `cctb`, `dctb`, `fctb`, `wctb`, `pltt`, or `PLTE`) with a matching `resource_id`, the emulator records `resolved` state plus the imported asset id/name and resource metadata. StackImport JSON palette payloads are parsed into script-visible color count, first/last colors, and tab-delimited normalized `#RRGGBB` colors. `xLine` consumes those active palette colors for classic color indexes when available. Missing or empty calls record `missing` or `empty`. | PR 7d slice. Future work should apply the resolved palette beyond QuickDraw line primitives once palette-aware paint/compositing is implemented. |
| `HyperTint` | Emulated | Records HyperTint timing/delay/options as runtime-only compatibility state and leaves rendering unchanged. | PR 7d slice. Future work should map HyperTint/AddColor resources to card/background paint layers or overlays. |
| `xCIcon3` | Emulated | Resolves imported `cicn`/`ICON` resources by ID and creates a transparent compatibility image part centered on the supplied classic point. | Future work should remove/reuse transient button-state icon overlays when imported scripts restore control state. |
| `xClip` | Emulated | Parses a classic rect, records runtime-only QuickDraw clip-rect intent, and returns the normalized rect in `it`/`the result`. | PR 7e slice. Future work should apply the clip to a paint-layer/overlay renderer once transient QuickDraw drawing is modeled. |
| `xLine` | Emulated | Parses start/end classic points plus pen size and color, records QuickDraw line intent, increments a line counter, returns a normalized line tuple, and renders the clipped line into the current card paint layer using the current `xClip` rect when present. The line renderer maps color indexes through active `HTUDefPal` normalized palette globals when available, with grayscale fallback for unmapped indexes. | PR 7e slice. Future work should broaden QuickDraw drawing beyond line primitives and apply palette state to additional paint/compositing surfaces. |
| `HTTB1TS` | Emulated | Parses destination/source classic rects, transfer-mode options, and VBL/noVBL options for HyperTint temp-buffer-to-screen tile copies; records runtime-only tile-copy intent and count. | PR 7f slice. Future work should composite the HyperTint temp buffer into the real card/overlay paint layer for dropped-page animation. |
| `Picture` | Emulated | Resolves an imported picture resource by classic name/metadata and creates an image-backed compatibility window part on the current card. Script-visible window existence, `rect`, `loc`, `scroll`, `dithering`, `show window`, and `close window <name>` state are modeled through runtime globals and the image part. Missing assets set a nonempty `the result` diagnostic. | PR 7g slice. Future work should implement exact scroll/crop rendering and classic floating-window compositing. |
| `AddColor` | Known unsupported | Sets `the result` to `XCMD 'AddColor' is known but is not emulated yet.` | Planned/research: inspect common AddColor resource formats and map color overlays to Hype parts, paint layers, or theme metadata. Depends on AddColor rendering decisions. |
| `ColorizeCard` | Known unsupported | Same unsupported diagnostic. | Research with AddColor family; likely card/background color overlay conversion. |
| `ColorizeHC` | Known unsupported | Same unsupported diagnostic. | Research with AddColor family; determine whether global HyperCard UI behavior has a useful Hype equivalent. |
| `ColorTools` | Known unsupported | Same unsupported diagnostic. | Research with AddColor family; may be tooling-only and not useful at runtime. |
| `CompileIt` | Known unsupported | Same unsupported diagnostic. | Research needed. CompileIt compiled HyperTalk or external code should not be loaded directly; possible plan is source-preserving diagnostics only. |
| `CompileIt!` | Known unsupported | Same unsupported diagnostic. | Same as `CompileIt`. |
| `FullPrint` | Known unsupported | Same unsupported diagnostic. | Planned/research: map common print/report flows to Hype export or print APIs, gated by normal user consent. |
| `PrintReport` | Known unsupported | Same unsupported diagnostic. | Same as `FullPrint`; identify expected report templates and output behaviors. |
| `ReadWrite` | Known unsupported | Same unsupported diagnostic. | Research needed. File access must map to Hype's consented file APIs, not arbitrary legacy paths. |
| `FileIO` | Known unsupported | Same unsupported diagnostic. | Research needed. Candidate for a scoped file-read/write emulator if stack intent can be safely represented. |
| `OpenFile` | Known unsupported | Same unsupported diagnostic. | Research needed. Any file picker/open behavior must be user-consented and sandbox-aware. |
| `SaveFile` | Known unsupported | Same unsupported diagnostic. | Research needed. Candidate for export/save-panel workflows rather than direct filesystem writes. |
| `SerialPort` | Known unsupported | Same unsupported diagnostic. | Research needed. Serial device access is platform- and permission-sensitive; likely deferred. |
| `Modem` | Known unsupported | Same unsupported diagnostic. | Research needed. Legacy modem semantics likely have no direct Hype equivalent. |
| `AppleEvents` | Known unsupported | Same unsupported diagnostic. | Unsupported by design as a generic bridge. Specific, safe AppleEvent-like behaviors may be modeled as explicit Hype features later. |
| Any other discovered `XCMD` | Unknown | Sets `the result` to `Can't Load External: XCMD '<name>' is not available in Hype.` | Research case by case from imported stack inventory, public docs, and observed scripts. Add explicit registry entries before implementing. |

## XFCN Mapping

| XFCN name | Current support | Current behavior | Planned support or research needs |
| --- | --- | --- | --- |
| `ExternalVersion` | Emulated | Returns `Hype HyperCard compatibility layer`; leaves `the result` empty. | Planned: consider returning a structured/versioned compatibility string when the layer has formal versions. |
| `XCMDVersion` | Emulated | Alias of `ExternalVersion`; returns `Hype HyperCard compatibility layer`. | Same as `ExternalVersion`. |
| `HypeVersion` | Emulated | Hype-native compatibility function; returns `Hype HyperCard compatibility layer`. | Planned: align with app/build version once runtime version APIs are stable. |
| `xMemory` | Emulated | Function-style alias for Myst scripts that call `xMemory(1)` despite the legacy resource being an XCMD; returns the same deterministic positive value as the XCMD path. | Same as XCMD `xMemory`. |
| `xVirtual` | Emulated | Returns deterministic `0`/false-style environment information and records arguments in runtime-only compatibility state. | Planned: refine if future imported scripts require virtual-memory-specific behavior. |
| `xDepth` | Emulated | Returns the current compatibility display depth, defaulting to `8`, and shares state with `SetMode`/`GetMode`. | PR 6f slice. Myst startup uses this to avoid the classic 256-color warning path when compatibility depth is already 8. |
| `variant` | Emulated | Returns deterministic `2.1` compatibility version text so Myst's HyperCard 2.1 feature checks take the normal pass-through path. | PR 6h slice. Future work can bind this to a formal compatibility-layer version if imported scripts need more detailed versioning. |
| `movieInfo` | Emulated | Resolves an imported QuickTime asset by classic path/name and returns CR-delimited repository-backed metadata: name, asset, path, type, byte count, bounds, duration, and timescale. Missing assets set `the result` to `File not found.` | PR 5e slice. Future work should fill exact QuickTime duration/timescale and track metadata when imported movie parsing exposes it. |
| `xSetSoundVol` | Emulated | Function-style alias for Myst scripts that call `xSetSoundVol(origVol)`; stores and returns the clamped classic volume. | Same as XCMD `xSetSoundVol`. |
| `xGetSoundVol` | Emulated | Returns the current runtime compatibility sound volume, defaulting to `255`. | Planned: bind classic volume to non-video imported audio playback once that playback path is modeled. |
| `GetMode` | Emulated | Returns the current runtime compatibility display mode/depth, defaulting to `c,8`. | Planned: refine return format if imported Myst probes require a different classic `GetMode` shape. |
| `AddColorVersion` | Known unsupported | Sets `the result` to `XFCN 'AddColorVersion' is known but is not emulated yet.` | Planned/research: implement once AddColor import/rendering support has a compatibility version story. |
| `ReadFile` | Known unsupported | Same unsupported diagnostic. | Research needed. Candidate for scoped, user-consented file reads, possibly using Hype's existing file tool model. |
| `WriteFile` | Known unsupported | Same unsupported diagnostic. | Research needed. Candidate for scoped, user-consented file writes or export flows. |
| `Directory` | Known unsupported | Same unsupported diagnostic. | Research needed. Directory listing must be sandbox-aware and user-consented. |
| Any other discovered `XFCN` | Unknown | Sets `the result` to `Can't Load External: XFCN '<name>' is not available in Hype.` | Research case by case from imported stack inventory, public docs, and observed scripts. Add explicit registry entries before implementing. |

## Implementation Checklist

Use this checklist when promoting a row from unsupported or research-needed to
emulated:

1. Add the legacy name and aliases to `HyperCardExternalRegistry.defaultEntries`.
2. Implement behavior in Swift using Hype model/runtime APIs only.
3. Preserve the security rule: do not load bundles, execute native resources,
   shell out, invoke generic AppleEvents, or access arbitrary files.
4. Add parser/interpreter tests for the external's command or function syntax.
5. Add import/report tests when the external appears as a resource.
6. Document argument handling, returned value, `the result`, document mutation,
   and any intentional deviations from HyperCard.

## Research Backlog

| Topic | Why it matters | Next evidence to gather |
| --- | --- | --- |
| AddColor resource behavior | Common visual extension for many colorized HyperCard stacks. | Collect sample stacks with AddColor resources and compare expected card/background rendering. |
| File I/O externals | Many stacks used externals for data import/export before HyperTalk had enough file support. | Catalog scripts using `FileIO`, `ReadWrite`, `ReadFile`, `WriteFile`, `OpenFile`, and `SaveFile`; separate picker workflows from direct path access. |
| Printing/report externals | Business stacks often relied on print formatting extensions. | Collect examples using `FullPrint` and `PrintReport`; identify whether Hype export/print surfaces can express them. |
| Device/system integration | Serial, modem, and AppleEvent externals can affect host system state. | Decide which behaviors deserve explicit Hype-native APIs and which remain unsupported by design. |
| Third-party external inventory | The external ecosystem was broad and stack-specific. | Use import reports from real stacks to build a frequency-ranked compatibility queue. |
