# SQLite Stack Storage

Hype stores `.hype` documents as self-contained packages backed by SQLite.

```text
Example.hype/
  manifest.json
  stack.sqlite
```

`manifest.json` identifies the package format and schema version and stores the
SHA-256 checksum of `stack.sqlite`. `stack.sqlite` is the canonical store for
stack content.

## Goals

- Keep stack files self-contained and portable.
- Store layout, scripts, object content, SpriteKit scenes, assets, themes, paint
  layers, and AI context inside SQLite tables.
- Keep runtime code working with value models (`HypeDocument`, `Stack`, `Card`,
  `Part`, `SpriteAreaSpec`, `SceneSpec`) instead of live database rows.
- Provide fast indexed search through SQLite FTS5.
- Make corrupted or suspicious stacks diagnosable with ordinary SQLite tools.

## Architecture

`HypeSQLiteStackStore` owns package read/write, schema creation, round-trip
mapping, FTS indexing, and diagnostics.

The current runtime boundary remains:

```text
SQLite package <-> HypeSQLiteStackStore <-> HypeDocument value graph <-> StackRuntime/UI
```

This avoids leaking SQLite handles, managed objects, AppKit, SpriteKit, SceneKit,
AVFoundation, or network objects into the persistent model.

## Schema Strategy

The schema uses normalized, queryable tables for the core Hype taxonomy:

- `stacks`
- `backgrounds`
- `cards`
- `parts`
- `scripts`
- `assets`
- `ai_context_sources`
- `ai_context_items`
- `themes`
- `paint_layers`
- `constraints`
- `sprite_areas`
- `scenes`
- `scene_nodes`
- `search_fts`

Rows also carry `payload_json` for exact value-model reconstruction. This is an
intentional bridge: high-value query fields are relational and indexed now, while
sparse type-specific fields remain lossless without prematurely exploding the
schema for every part subtype.

## Search

`search_fts` indexes:

- stack/card/background/part names and scripts
- part text, help, menu, popup, URL, and search fields
- SpriteKit scene/node names, label text, and scripts
- asset names, tags, and provenance
- AI context summaries and text chunks

Search is derived data. If it drifts, it can be rebuilt from the relational
tables and payload rows.

## Diagnostics

The store exposes `validate(packageURL:)`, which runs:

- `PRAGMA integrity_check`
- `PRAGMA foreign_key_check`
- key table counts
- missing SpriteKit asset reference checks
- FTS entry counts

The database also defines diagnostic views:

- `v_card_layout`
- `v_object_scripts`
- `v_missing_asset_refs`

## Save And Recovery

Normal document saves and recovery snapshots both use SQLite packages. The
in-memory undo/coalescing path still uses deterministic JSON snapshots for
equality only; those snapshots are not the `.hype` file format.

SQLite WAL is enabled while writing, checkpointed, and then reset to DELETE
journal mode before the package is finalized so the package remains
self-contained. Read, search, and validation open the database read-only and do
not create WAL/SHM sidecars.
