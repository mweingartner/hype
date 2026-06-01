# HyperCard Import and XCMD/XFCN Compatibility

## Scope

Hype imports original HyperCard stacks into normal `.hype` documents through a
safe structural converter. The importer is not a classic Mac emulator. It parses
legacy stack data, preserves unsupported source artifacts, maps supported cards,
backgrounds, buttons, fields, and scripts into `HypeDocument`, and routes
external calls through a Swift emulation registry.

Primary references used for the implementation:

- [Library of Congress HyperCard Stack format note](https://www.loc.gov/preservation/digital/formats/fdd/fdd000537.shtml)
- [hypercard.org reverse-engineered stack file format](https://hypercard.org/hypercard_file_format/)
- [MacTech XCMD Cookbook](https://preserve.mactech.com/articles/mactech/Vol.04/04.06/XCMDCookBook/index.html)
- [CompileIt manual](https://hypercard.org/CompileIt_Manual.pdf)

## Import Pipeline

1. `HyperCardInputNormalizer` reads the selected file's data fork and attempts
   to locate a resource fork via `..namedfork/rsrc` or an AppleDouble `._Name`
   sidecar.
2. `HyperCardBlockParser` validates and walks the block stream with hard size
   and count limits. It recognizes stack blocks such as `STAK`, `BKGD`, `CARD`,
   `LIST`, `PAGE`, `BMAP`, and `TAIL`.
3. `MacResourceForkReader` parses the classic resource map and reports resource
   types and sizes. It never executes resource code.
4. `HyperCardToHypeConverter` creates a `HypeDocument`, maps readable structure,
   and attaches `LegacyStackImportMetadata`.
5. The Hype app exposes the flow through `File > Import HyperCard Stack...`.

For the expected portable package layout used by classic stack import tooling,
see [`ClassicHyperCardStackManifest.md`](ClassicHyperCardStackManifest.md).

## XCMD/XFCN Emulation Plan

Classic HyperCard extended HyperTalk through native code resources named XCMDs
and XFCNs. Hype treats those resources as untrusted legacy code and never loads
or executes them. Compatibility is provided through `HyperCardExternalRegistry`.
The current per-external support map lives in
[`HyperCardExternalMapping.md`](HyperCardExternalMapping.md).

The registry models the behavior that matters to scripts:

- Command-style XCMD calls parse as `Statement.externalCommand`, for example
  `SetCursor "watch"`.
- Parameterless single-identifier lines dispatch as classic handler commands
  when the normal HypeTalk message path contains a matching handler, for example
  `resetDrawers`.
- Function-call syntax dispatches to matching handler functions in the normal
  message path before falling back to built-ins and emulated XFCNs, for example
  `theAdjust()`. If a local `go` changes the current card earlier in the same
  handler, later function calls use that destination card as the lookup context.
- Validator object-reference checks accept classic self-card references such as
  `this card` and `current card`.
- Validator object-reference checks skip variable-driven object references such
  as `go to card x` or `button which`; those remain runtime-resolved.
- Validator hook-context checks treat card/background lifecycle handlers in
  stack scripts as valid because those messages pass up through the normal
  HyperCard-style hierarchy to the stack.
- Function-style XFCN calls use ordinary function syntax, for example
  `put HypeVersion() into field "status"`.
- Parameters are passed as evaluated HypeTalk strings.
- The emulated external returns a value, a `the result` diagnostic, an optional
  modified document, optional runtime globals, optional visual-effect intent,
  and an optional pass-message flag.
- Unknown externals set `the result` to `Can't Load External...` and continue
  without crashing the stack.

Adding an emulator should follow this sequence:

1. Add the legacy external name to `HyperCardExternalRegistry.defaultEntries`.
2. Implement the behavior in Swift using Hype model APIs only.
3. Do not call shell commands, load bundles, invoke AppleEvents, open arbitrary
   files, or use network access unless that behavior goes through Hype's normal
   user-consented feature gates.
4. Add an import/report test if the external has a resource form.
5. Add parser/interpreter tests covering command syntax, function syntax, `the
   result`, document mutation, and pass-message behavior if applicable.

## Current Compatibility

Implemented:

- Safe stack block parsing.
- Safe resource fork parsing.
- Structural conversion for stack size, backgrounds, cards, button records,
  field records, part text, and scripts.
- Route-only script translation for StackImport-era movie-click card scripts
  that fail full HypeTalk parsing but contain explicit cross-stack
  `go ... of stack ...` commands. The generated handler is parser-validated
  HypeTalk, preserves the final project-navigation behavior needed by Myst
  age-link/return movies, and keeps unsupported movie/window choreography inert
  in comments.
- Original data/resource fork preservation when under the configured size limit.
- Import report with block summary, resource summary, unsupported feature notes,
  and XCMD/XFCN inventory.
- XCMD command parser path.
- XFCN fallback through the built-in function dispatcher.
- Runtime degradation for unknown externals.
- Myst-facing `HTLock` compatibility records a runtime-only lock mode and
  continues execution without blocking drawing.
- Myst-facing `playQT`/`Movie`/`closemoovs` compatibility resolves imported
  video assets by classic name, creates repository-backed video parts, supports
  loop intent for `playQT`, uses basic classic point placement for `Movie`, and
  tears down compatibility movie parts. Audio-only QuickTime replacements
  imported as `*-modern-audio.m4a` keep classic movie lookup semantics but
  create hidden 1x1 playback parts so ambient `playQT` calls do not display a
  movie controller. Myst-style `set the ... of window ...`
  statements record runtime-only window state and update compatibility video
  parts for common properties such as `loop`, `rate`, `movie`, `windowRect`,
  `windowLoc`, `windowName`, `audioLevel`, and `mute`.
- Myst-facing `HTVisual` compatibility records transition intent and feeds the
  existing Hype visual-effect result channel.
- Myst-facing `DeCurse` compatibility records cursor override/remove intent and
  cursor resource arguments as runtime-only state.
- Myst-facing `xMemory` compatibility returns a deterministic positive value in
  both XCMD and function-style paths; `xVirtual` returns deterministic false/0
  environment information.
- Myst-facing `xSetSoundVol`/`xGetSoundVol` compatibility records and returns
  a classic 0...255 runtime-only sound volume, defaulting to 255, and
  `xSetSoundVol` updates active compatibility-created video parts while later
  QuickTime parts inherit the current volume.
- Myst-facing `SetMode`/`GetMode` compatibility records and returns classic
  display mode/depth runtime-only state, defaulting to `c,8`.
- Myst-facing `HTAddPict`, `HTChangePict`, `HTSavePict`, and `xCIcon3`
  compatibility resolves imported resource image assets by classic name or
  resource ID and creates runtime image parts on the current card.
  `HTAddPict` and `HTChangePict` crop decoded image resources for classic
  `"srcRect", <rect>` arguments, record recognized transfer-mode names, and
  composite recognized byte-wise transfer modes into the current card paint
  layer when image pixels can be decoded. `HTSavePict` records clipboard-save
  intent, captures current-card paint-layer pixels for clipboard destinations
  when available, and `HTAddPict` clipboard restores remove matching transient
  compatibility overlays before restoring that captured image.
- Myst-facing `HTUDefPal`, `HyperTint`, and `HTRemove` compatibility records
  stack-level palette/tint setup as runtime-only state, resolves imported
  palette resources by `resource_type`/`resource_id` metadata when available,
  parses StackImport palette JSON into normalized `#RRGGBB` color globals, and
  clears transient compatibility parts during stack teardown.
- Myst-facing `xClip` and `xLine` compatibility records QuickDraw intent and
  renders clipped line primitives into the current card paint layer, using
  active `HTUDefPal` normalized palette colors for classic color indexes when
  available and grayscale indexes otherwise. This gives tower-rotation and
  similar transient drawing scripts a persisted visual surface instead of only
  script-global evidence.
- `snd ` resource conversion to `audioClip` assets in `AssetRepository` via
  `stackimport_snd_to_wav()` (pure Swift path) and streaming resource
  payload callbacks (C importer path).
- HypeTalk `play` resolves imported sound names through the same classic media
  lookup used by compatibility QuickTime/XCMD paths, including case and
  whitespace normalization and collapsed word separators. CLI validation uses
  that lookup for literal sound names and leaves variable-driven `play`
  expressions to runtime.
- StackImport package resource consumption for converted PNG/image, audio,
  video, JSON, and text artifacts. Multi-artifact resources keep related
  metadata with the primary asset; standalone JSON/text resources are inert
  `placeholderAsset` entries.
- StackImport package font-table diagnostics preserve classic font IDs/names,
  report whether each font is available on the host Mac, and write deterministic
  available fallback font names into imported stack defaults and button/field
  text when the original classic/custom font is missing.
- StackImport project import treats stack-library entries marked
  `contentStack=true` as shared content/library stacks and copies their
  imported repository assets into the other generated `.hype` packages with
  `shared_from_content_stack` provenance metadata. This keeps each generated
  document self-contained while allowing classic media/resource lookup to find
  shared content-stack assets by name or resource ID.
- StackImport package, project-stack, and project import summaries report
  source package paths, generated `.hype` package byte counts, and import
  durations. Project summaries also expose top-level source/output path arrays
  in import order. Debug/live probes use these fields to disambiguate same-named
  stacks and profile self-contained package growth/import cost as Myst
  content-stack resources and loose media are imported.

Not yet implemented:

- WOBA bitmap decompression and paint-layer reconstruction.
- Exact classic compositing for every PICT/icon transfer-mode edge case, full
  resolved-palette application beyond QuickDraw line color indexes, fully
  composited clipboard capture, and broader paint-layer-backed overlay reuse
  beyond current byte-wise picture, QuickDraw line, and paint-layer clipboard
  primitives.
- Full classic QuickTime callback timing, controller flags, exact window
  semantics, and fade timing.
- AddColor rendering.
- Native replacements for most third-party XCMDs.
- Disk-image, StuffIt, and archive extraction.
- Full HyperTalk compatibility for every classic command and property.

## Security Rules

- Treat every imported byte as hostile.
- Enforce block/resource size limits before allocating or decoding.
- Preserve native resources as data only.
- Do not execute classic 68K/PPC code, dynamically load converted code, or shell
  out to legacy tools during import.
- Prefer explicit emulators over generic native bridges.
- Keep converted stacks portable: the `.hype` document carries supported content
  plus legacy metadata; it must not depend on the original file path.
