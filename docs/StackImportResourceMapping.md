# StackImport Resource Mapping

This document tracks how Hype should consume resource events and converted
artifacts from `stackimport`, how those artifacts enter the `AssetRepository`,
and which Hype object they can instantiate.

It is a target mapping. Current Hype support is narrower: the Swift importer
and C importer already convert classic `snd ` resources into
`AssetKind.audioClip` assets, while most other converted resource families are
still preserved as report metadata or original fork evidence until the
`LegacyImportBundle`/asset-import path in
[`HyperCardImportPathImplementationPlan.md`](HyperCardImportPathImplementationPlan.md)
is implemented.

## Import Rules

- Treat every resource payload as hostile input. Bounds checks and conversion
  diagnostics belong in the import bundle before any value-model mutation.
- Preserve native resource evidence even when a converted artifact is also
  imported. Native bytes are provenance, not executable content.
- Never execute `XCMD`, `XFCN`, `CODE`, `DRVR`, `dcmp`, 68K, or PowerPC
  resources. Runtime compatibility must go through Swift emulators documented
  in [`HyperCardExternalMapping.md`](HyperCardExternalMapping.md).
- Import converted media as stack-embedded assets. A converted `.hype` must not
  depend on the original stack file or temporary `.xstk` package.
- Represent multi-output resources as one logical asset when the files are
  semantically inseparable. Use `Asset.data` for the primary renderable payload,
  `Asset.files` for related media such as textures, masks, animations, skeletons,
  previews, and metadata files, and `Asset.metadata` for typed JSON/text/scalar
  records.
- Do not automatically place a resource on a card unless the stack structure,
  AddColor data, PICT placement evidence, or a future explicit importer rule
  identifies where it belongs.
- Asset Browser instantiation should be explicit and repeatable: selecting an
  imported asset should create the Hype object listed below with an `AssetRef`
  or copied bytes, depending on the existing part model.

## Resource Event To Hype Mapping

| Resource family | StackImport artifact | Hype import target | Instantiates |
| --- | --- | --- | --- |
| `snd ` | WAV payload plus native resource record | `AssetKind.audioClip`, tagged `hypercard-import`, `sound-resource`, `resource-snd` | Asset Browser creates an audio-capable scene node or future audio part. Today it is repository content only unless a script/tool uses it. |
| `ICON`, `ICN#`, `SICN`, `icm#`, `ics#`, `icl4`, `icl8`, `icm4`, `icm8`, `ics4`, `ics8` | PNG payloads, dimensions, mask/composition metadata when available | `AssetKind.imageTexture`; multi-image lists may become `spriteSheet` only when grid/slice metadata is reliable | Asset Browser creates an `image` part by default. For sprite areas, it can create a `SceneSpec.NodeKind.sprite` using the asset. |
| `cicn` | JSON metadata plus decoded PNG | `AssetKind.imageTexture` with JSON in `Asset.metadata` or a metadata `AssetFile` | Asset Browser creates an `image` part or sprite node. Metadata remains provenance. |
| `CURS`, `crsr` | PNG payloads plus hotspot/dimension JSON | `AssetKind.imageTexture` with hotspot metadata in `Asset.metadata`; color/mono variants may be related `Asset.files` | Asset Browser creates an `image` part by default; future cursor tooling may bind hotspot metadata to pointer state, not a separate part. |
| `PAT `, `PAT#`, `ppat`, `ppt#` | Pattern PNGs plus JSON pattern/pixmap metadata | `AssetKind.imageTexture`; tiled variants, masks, and monochrome/color previews can be related `Asset.files` | Asset Browser creates an `image` part or sprite/tile texture. Future fill controls may use these as shape/card/background fill assets. |
| `PICT` | PNG payload from the narrow PICT adapter plus native resource record | `AssetKind.imageTexture` | If placement evidence exists, import may create an `image` part on the owning card/background; otherwise Asset Browser creates an `image` part. |
| `HCbg`, `HCcd` | AddColor/HyperCard card-background JSON and any referenced decoded images | Legacy import metadata plus image assets for referenced media | May instantiate `shape`, `image`, or paint-layer content only after AddColor rendering rules are defined. Until then it is metadata/evidence. |
| `STR `, `STR#`, `TEXT`, `TwCS` | UTF-8 text or JSON string-list payloads | Legacy metadata artifact, metadata entry on a related asset, or optionally searchable AI/context text if explicitly promoted later | Does not instantiate a visual object by default. Future explicit action may create `field` parts or AI context notes. |
| `styl`, `TxSt`, `FTBL`-adjacent style data | JSON style/font metadata | Legacy metadata artifact and script/text provenance | Does not instantiate a standalone object. Used to improve imported `field`/`button` text styling when tied to stack structure. |
| `FONT`, `NFNT`, `finf`, `sfnt`, `FWID` | Font metadata or native font bytes when supported | Legacy metadata; possible embedded font asset only after a font policy exists | Does not instantiate a part. Imported text should degrade to available macOS fonts until font embedding is designed. |
| `clut`, `CTBL`, `actb`, `cctb`, `dctb`, `fctb`, `wctb`, `pltt`, `PLTE` | JSON color-table or palette payloads, optionally preview PNGs | Logical palette asset using `Asset.metadata` plus related preview `Asset.files`; possible theme/palette candidate | Does not instantiate a part. Future theme import may create stack theme tokens or swatches. |
| `MENU`, `MBAR`, `DITL`, `CNTL`, `DLOG`, `WIND`, `ALRT` | JSON UI/menu/dialog metadata | Legacy metadata artifact | Does not instantiate by default. Future compatibility conversion may create `menu`, `button`, `field`, `toggle`, `slider`, `segmented`, `divider`, or modal templates when layout and behavior are understood. |
| `FREF`, `BNDL`, `cfrg`, `vers`, `SIZE`, `PICK`, `KBDN`, `PAPA`, `LAYO`, `RECT`, `TOOL`, `ROv#`, `RSSC`, `KCHR` | JSON metadata | Legacy metadata artifact with search/provenance text | Does not instantiate a visual object. Use for diagnostics, compatibility reporting, and future specialized import rules. |
| `XCMD`, `XFCN`, `xcmd`, `xfcn` | Native resource record; optional disassembly text artifact | Legacy external inventory and optional disassembly metadata | Never instantiates executable code. Script calls route through `HyperCardExternalRegistry`; unsupported externals produce diagnostics. |
| `CODE`, `DRVR`, `dcmp`, `68k!`, `ppc!`, `ppcc`, `ppci`, `ppct`, `CDEF`, `MDEF`, `WDEF`, `LDEF`, `GDEF`, `PACK`, `INIT`, `FKEY` | JSON headers and/or disassembly text when available | Legacy metadata/disassembly artifact | Never instantiates runtime code or plugins. May inform compatibility diagnostics only. |
| `MOOV`, `MooV`, `moov`, `Midi`, `MIDI`, `midi`, `SONG`, `SOUN`, `Tune`, `Ysnd`, `csnd`, `ESnd`, `esnd`, `nsnd` | Native media record; converted media only when stackimport adds a safe converter | Target `AssetKind.videoClip` or `AssetKind.audioClip` when converted to supported formats | Asset Browser creates `video` parts for video assets and audio-capable scene/future audio parts for audio assets. Native-only records do not instantiate. |
| `icns`, `ic04`, `ic05`, `ic07`, `ic08`, `ic09`, `ic10`, `ic11`, `ic12`, `ic13`, `ic14`, `ich#`, `ich4`, `ich8`, `icp4`, `icp5`, `icp6`, `ih32`, `il32`, `is32`, `it32`, mask resources such as `h8mk`, `l8mk`, `s8mk`, `t8mk` | Future decoded PNGs or native evidence | `AssetKind.imageTexture` when decoded | Asset Browser creates `image` parts or sprite nodes once decoded support exists. |
| Unknown or unsupported resource types | Native resource record, byte count/hash, diagnostics | Legacy metadata/evidence only | Does not instantiate. |

## Asset Browser Instantiation Defaults

| Asset kind | Default object | Binding rule |
| --- | --- | --- |
| `imageTexture` | `PartType.image` | Use repository asset reference if/when image parts gain `AssetRef`; otherwise copy bounded image bytes into the part following the existing image-part model. |
| `spriteSheet` | Sprite area node or `PartType.image` fallback | Prefer `SceneSpec.NodeKind.sprite` with slice metadata when launched from a sprite-area context. Outside sprite areas, create an `image` part preview. |
| `tileSet` | Sprite area tile map | Create or target a `spriteArea` and instantiate `SceneSpec.NodeKind.tileMap` with tile dimensions from asset metadata. |
| `audioClip` | Audio scene node or future audio part | Use an asset reference from SpriteKit scene audio nodes. Until a standalone audio part exists, keep imported sounds in the repository. |
| `videoClip` | `PartType.video` | Bind through the existing video part path once repository-backed video references are supported. |
| `model3D` | `PartType.scene3D` | Set `Part.scene3DAssetRef` to the selected repository asset. |
| `particlePreset` | SpriteKit emitter node | Instantiate inside a `spriteArea` as `SceneSpec.NodeKind.emitter`. |

## Implementation Checklist

Use this checklist when promoting a resource family from preserved evidence to
active Hype content.

1. Add or update the `stackimport` resource event mapping in Hype's
   `LegacyImportBundle` layer.
2. Import converted media bytes through one asset importer path with resource
   type, id, name, native hash, artifact kind, MIME type, and conversion
   diagnostics in provenance.
3. Preserve metadata JSON or typed values in legacy import metadata, linked to
   any derived media asset through a stable artifact id.
4. Instantiate Hype parts only when a deterministic placement rule exists.
5. Add focused tests for safe decoding, duplicate names, malformed resources,
   oversized payload rejection, asset provenance, and storage round trip.
6. Update
   [`HyperCardImportAndXCMDCompatibility.md`](HyperCardImportAndXCMDCompatibility.md)
   when the family becomes user-visible import behavior.

## Current StackImport Typed Coverage

As of the remediation plan reviewed on 2026-05-26, stackimport reports typed or
converted coverage for:

`ICON`, `ICN#`, `CURS`, `PAT `, `PAT#`, `PLTE`, `clut`, `CTBL`, `actb`,
`SICN`, `icm#`, `ics#`, `icl4`, `icl8`, `icm4`, `icm8`, `ics4`, `ics8`,
`cfrg`, `cctb`, `dctb`, `fctb`, `wctb`, `pltt`, `ppat`, `ppt#`, `HCbg`,
`HCcd`, `STR `, `STR#`, `TEXT`, `TwCS`, `vers`, `SIZE`, `finf`, `CNTL`,
`DLOG`, `WIND`, `MENU`, `DITL`, `MBAR`, `ALRT`, `FREF`, `BNDL`, `ROv#`,
`PICT`, `snd `, `RSSC`, `TxSt`, `RECT`, `TOOL`, `PICK`, `KBDN`, `PAPA`,
`XCMD`, `XFCN`, `LAYO`, `CODE`, `DRVR`, `dcmp`, `styl`, `KCHR`, `cicn`,
`crsr`, `xcmd`, and `xfcn`.

When stackimport adds a new converted resource family, update the mapping table
above before wiring the payload into Hype import code.
