# HyperCard Import Path Implementation Plan

## Context

Hype currently has two HyperCard import paths:

- `HyperCardToHypeConverter`, a Swift structural parser that preserves original
  forks and performs narrow conversion such as `snd ` to repository audio
  assets.
- `StackImportCImporter` plus `StackImportPackageConverter`, which runs the
  stackimport C importer, reads the generated `.xstk` package, maps structure
  into Hype, and imports converted `.wav` artifacts by scanning package paths.

The newest stackimport remediation plan moves stackimport toward a single
resource event/conversion pipeline: native resource evidence, converted media
payloads, typed metadata, diagnostics, output artifact summaries, and source
manifest data should all flow through one owned event model. Hype should align
with that direction instead of continuing to infer assets from package
filenames.

## Goals

- Build a composable import path where structure, media conversion, provenance,
  diagnostics, and persistence are separate stages with clear contracts.
- Populate `AssetRepository` from typed imported media events, not ad hoc file
  scans.
- Preserve bundled metadata plus media artifacts from stackimport, including
  multi-artifact resources such as metadata JSON plus PNG/WAV outputs.
- Track provenance for imported assets, scripts, cards, backgrounds, and parts
  without executing legacy code or depending on original file paths.
- Keep converted `.hype` documents self-contained and diagnosable through
  SQLite tables and value-model payloads.

## Non-Goals

- Do not emulate classic Mac runtime behavior beyond existing Swift
  compatibility registries.
- Do not execute XCMD/XFCN, 68K, or PowerPC code.
- Do not make the `.hype` file depend on the generated `.xstk` package after
  conversion.
- Do not introduce silent decoder fallbacks for breaking persisted model shape;
  use the document-version migration workflow when required.

## Target Architecture

Introduce a Hype-owned import intermediate representation:

```text
source forks
  -> stackimport / Swift parser
  -> LegacyImportBundle
  -> HypeImportBuilder
  -> HypeDocument
```

`LegacyImportBundle` should contain:

- stack structure: stack, background, card, part records
- script records: owner kind, owner legacy id, source text, parse status
- resource records: native resource id/type/name/hash/byte count
- media artifacts: bytes, MIME type, dimensions/duration when known
- metadata artifacts: typed JSON or typed Swift values
- diagnostics: parser/conversion warnings with source offsets where available
- source manifest: block/resource offsets, hashes, package artifact paths

`HypeImportBuilder` should be the only stage that mutates `HypeDocument`. It
maps structure to value-model objects, imports media into `AssetRepository`,
attaches scripts, records provenance, and builds `LegacyStackImportMetadata`.

## Provenance Model

Extend provenance in two layers.

1. Asset provenance:
   - Add `classicHyperCardImport` to `AssetOrigin`, or add a legacy import
     detail object under `AssetProvenance`.
   - Preserve source format, source file name, data/resource fork hashes,
     resource type, resource id, resource name, native resource hash,
     artifact kind, conversion pipeline, converter version, and diagnostics.
   - For multi-artifact resources, connect related assets and metadata through a
     stable import artifact id.

2. Core object provenance:
   - Add optional provenance metadata to `Stack`, `Background`, `Card`, and
     `Part`, or add a document-level provenance index keyed by object UUID.
   - Track legacy object kind, legacy id, block type, source offset when known,
     original name, script hash, import stage, and diagnostics.
   - Prefer a document-level index if the metadata grows quickly; prefer direct
     optional fields only for compact, commonly queried identity data.

This is a persisted model change. If new Codable keys are strictly optional and
decode cleanly for existing documents, a document version bump may not be
required. If keys are renamed, invariants become required, or storage needs new
normalized projections, follow the `HypeDocument.currentDocumentVersion`
migration workflow.

## Implementation Trajectory

### Phase 1: Contracts And Fixtures

- Define `LegacyImportBundle`, `LegacyImportResource`, `LegacyImportArtifact`,
  `LegacyImportObjectProvenance`, and `LegacyImportDiagnostic` in
  `Sources/HypeCore/HyperCardImport/`.
- Add fixture-driven tests that synthesize bundled resource metadata plus media
  artifacts without invoking stackimport.
- Update `StackImportPackageConverter` to read bundled artifact summaries when
  present while keeping existing `.wav` path scanning as compatibility fallback.

Completion:

- Existing imports still work.
- Tests prove one resource can emit metadata and media artifacts into the bundle.
- Missing or malformed artifact metadata produces diagnostics, not crashes.

### Phase 2: Asset Repository Import

- Add a small `LegacyAssetImporter` that converts `LegacyImportArtifact` values
  into `Asset` values.
- Support at least `audio/wav`, `image/png`, and `application/json` metadata
  relationships; JSON metadata should be preserved in legacy metadata unless it
  is also useful as a repository asset.
- Deduplicate asset names deterministically while preserving resource ids in
  provenance.
- Ensure every imported asset has tags such as `hypercard-import`,
  resource-type, and artifact kind.

Completion:

- Converted audio and image artifacts populate `AssetRepository` through the
  same code path.
- Asset provenance includes resource ids and source hashes.
- Search indexes include enough provenance text to find imported assets.

### Phase 3: Object And Script Provenance

- Preserve object provenance for stack, backgrounds, cards, parts, and scripts.
- Record scripts as disabled legacy source exactly once, with hashes and parse
  diagnostics attached to the object provenance.
- Add tests that prove card, part, and script provenance round trip through
  `HypeSQLiteStackStore`.

Completion:

- A converted document can answer where an imported part, card, script, and
  asset came from.
- Disabled legacy scripts remain parse-safe and never become executable by
  accident.

### Phase 4: StackImport Event Alignment

- Replace filename inference in `StackImportCImporter` with stackimport resource
  payload/event callbacks as they become available.
- Capture native resource records, converted payloads, typed metadata,
  diagnostics, and output artifact summaries into `LegacyImportBundle`.
- Keep callback filters explicit so Hype can request supported converted media
  without forcing every expensive conversion.

Completion:

- Package import, C callback import, and future corpus import use the same Hype
  bundle-to-document builder.
- Converted resource families added in stackimport require only artifact mapping
  code in Hype, not new package-specific scans.

### Phase 5: Persistence And Diagnostics

- Decide whether imported object provenance belongs in payload JSON only or also
  in normalized SQLite tables such as `legacy_object_provenance` and
  `legacy_import_artifacts`.
- If normalized tables are added, bump `HypeSQLiteStackStore.schemaVersion` and
  add validation/search projections.
- If value-model shape changes are breaking, bump
  `HypeDocument.currentDocumentVersion` and add migration tests.

Completion:

- SQLite validation can report missing imported asset references and malformed
  legacy provenance records.
- Search can find imported assets, scripts, cards, parts, and resource names.
- Opening an older `.hype` package does not rewrite it until save.

## Test Coverage

- Unit tests for `LegacyImportBundle` decoding and malformed artifact handling.
- Unit tests for `LegacyAssetImporter` covering WAV, PNG, duplicate names,
  unsupported MIME types, missing bytes, and provenance fields.
- Converter tests for bundled metadata plus media import data across multiple
  resources.
- Storage round-trip tests for asset and object provenance.
- Search/validation tests if normalized SQLite projections are added.
- Security regression tests for oversized artifacts, invalid resource ids,
  path traversal in artifact names, and unsupported native-code resources.
- Focused stackimport fixture tests gated on fixture availability, matching the
  existing `Resources.stak` pattern.

## Documentation

- Update `architecture.md` section 2.6 with the bundle/builder architecture.
- Update `architecture.md` section 4 with classic-import asset provenance.
- Update `docs/HyperCardImportAndXCMDCompatibility.md` with supported artifact
  families and safety rules.
- Update `docs/SQLiteStackStorageDesign.md` if schema or document-version
  behavior changes.
- Update `docs/ClassicHyperCardStackManifest.md` to map stackimport artifact
  summaries to Hype import bundle fields.

## Definition Of Done

- The import path no longer relies on package filename conventions for primary
  asset ingestion when stackimport provides typed metadata and media events.
- Imported assets, scripts, cards, backgrounds, and parts have inspectable
  provenance.
- Converted media assets are embedded in `.hype` and resolve through
  `AssetRepository`/`AssetRef` discipline.
- Unsupported or malformed resources are preserved as diagnostics/evidence, not
  silently dropped.
- Relevant focused tests and storage round trips pass, followed by
  `scripts/test.sh` before merge.
