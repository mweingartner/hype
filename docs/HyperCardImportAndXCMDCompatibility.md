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
- Function-style XFCN calls use ordinary function syntax, for example
  `put HypeVersion() into field "status"`.
- Parameters are passed as evaluated HypeTalk strings.
- The emulated external returns a value, a `the result` diagnostic, an optional
  modified document, and an optional pass-message flag.
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
- Original data/resource fork preservation when under the configured size limit.
- Import report with block summary, resource summary, unsupported feature notes,
  and XCMD/XFCN inventory.
- XCMD command parser path.
- XFCN fallback through the built-in function dispatcher.
- Runtime degradation for unknown externals.
- `snd ` resource conversion to `audioClip` assets in `AssetRepository` via
  `stackimport_snd_to_wav()` (pure Swift path) and streaming resource
  payload callbacks (C importer path).
- StackImport package resource consumption for converted PNG/image, audio,
  video, JSON, and text artifacts. Multi-artifact resources keep related
  metadata with the primary asset; standalone JSON/text resources are inert
  `placeholderAsset` entries.

Not yet implemented:

- WOBA bitmap decompression and paint-layer reconstruction.
- Automatic placement of PICT or other resource-derived images as card parts.
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
