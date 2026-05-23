# Classic HyperCard Stack Manifest

This document describes two related manifests for classic HyperCard import
work:

- The source manifest for one extracted classic Mac stack file.
- The generated package manifest for the `.xstk/` directory produced from that
  source.

The current portable importer does not yet emit every file listed below. This
manifest combines current importer behavior with the default resource
disassembly direction so the importer, test corpus, and reverse-engineering
tools have a shared target.

## Source Stack

A source HyperCard stack is one classic Mac file with two important forks and
optional filesystem metadata from the archive or extraction process.

### Data Fork

The data fork is the HyperCard stack block stream. It contains sequential blocks
such as:

| Block | Meaning |
| --- | --- |
| `STAK` | Stack metadata, stack script, card size, pattern table, and referenced block IDs. |
| `LIST` | Page table index and card ordering metadata. |
| `PAGE` | Card ID tables. |
| `BKGD` | Background layer records, parts, scripts, and contents. |
| `CARD` | Card layer records, parts, scripts, and contents. |
| `BMAP` | WOBA-compressed bitmap data for card and background art. |
| `FTBL` | Font table, when present. |
| `STBL` | Style table, when present. |
| `MAST` | Master block or reference table. |
| `PRNT` | Print settings. |
| `PRST` | Page setup. |
| `PRFT` | Report template. |
| `FREE` | Unused or free block space. |
| `TAIL` | End marker. |

Not every stack has every block. HyperBBS, for example, references `FTBL` ID
`0` and `STBL` ID `0` from `STAK`, but those blocks are absent. The source
manifest should preserve that distinction as missing referenced blocks, not as
an import crash.

### Resource Fork

The resource fork contains classic Mac resources attached to the stack file.
Relevant corpus types include:

| Type | Meaning |
| --- | --- |
| `XCMD` | 68K external command code resources. |
| `XFCN` | 68K external function code resources. |
| `PICT` | Picture resources. |
| `ICON` | Black-and-white icon resources. |
| `CURS` | Cursor resources. |
| `snd ` | Sound resources. |
| `HCbg` | HyperCard background resource data. |
| `HCcd` | HyperCard card resource data. |
| `xcmd` | Lowercase external command variant. |
| `xfcn` | Lowercase external function variant. |

For `XCMD` and `XFCN` resources, each resource should be described with:

- Resource type, such as `XCMD` or `XFCN`.
- Signed resource ID.
- MacRoman resource name.
- Resource attributes, such as purgeable, preload, protected, and related
  flags.
- Byte count and hash of the executable 68K code payload.

Example HyperBBS external inventory:

```text
XCMD #7030 "breakSPort"
XCMD #7031 "closeSPort"
XCMD #7032 "killSPort"
XCMD #7033 "sendSPort"
XCMD #7034 "setSPortBufferSize"
XCMD #7035 "configureSPort"
XCMD #7036 "XModem"
XCMD #7037 "sendSPortBytes"

XFCN #7030 "charsAvailable"
XFCN #7031 "recvChars"
XFCN #7032 "recvUpTo"
XFCN #7033 "sendSPortDone"
XFCN #7034 "SPortBufferSize"
XFCN #7035 "SPortVersion"
XFCN #7036 "SPortConfiguration"
XFCN #7037 "recvBytes"
```

### Filesystem Metadata

The source file can also carry classic Mac metadata from extraction:

- Finder type, often `STAK` for stack files.
- Creator and type metadata.
- Data fork byte size.
- Resource fork byte size.
- Archive path and original archive boundary.
- MacRoman filenames and resource names.

### Source Manifest Shape

For one source stack, the manifest should describe the source and its forks
before describing generated output files:

```yaml
source:
  archive: Communications/HyperBBS.sit
  extracted_path: HyperBBS_1.0/Home
  data_fork_bytes: 68800
  resource_fork_bytes: 57723
  finder_type: STAK
  sha256_data_fork: ...
  sha256_resource_fork: ...

data_fork:
  blocks:
    - type: STAK
      id: -1
      size: 18432
      offset: 0
    - type: MAST
      id: -1
      size: 512
      offset: 18432
    - type: LIST
      id: 8096
      size: 128
      offset: 18944
    - type: PAGE
      id: 10277
      size: 2048
      offset: 19072
    - type: BKGD
      id: 2282
      size: 448
      offset: 21120
    - type: BMAP
      id: 7740
      size: 256
      offset: 21568
    - type: PRNT
      id: 3372
      size: 192
      offset: 68576
    - type: TAIL
      id: -1
      size: 32
      offset: 68768
  referenced_tables:
    list_block_id: 8096
    font_table_id: 0
    style_table_id: 0
    missing_referenced_blocks:
      - FTBL #0
      - STBL #0

resource_fork:
  resources:
    - type: XCMD
      id: 6000
      name: deleteFile
      bytes: ...
    - type: XCMD
      id: 6001
      name: macBinify
      bytes: ...
    - type: XCMD
      id: 6002
      name: renameFile
      bytes: ...
    - type: XCMD
      id: 7030
      name: breakSPort
      bytes: ...
    - type: XFCN
      id: 6000
      name: deMacBinify
      bytes: ...
    - type: XFCN
      id: 6001
      name: fileInfo
      bytes: ...
```

## Generated Package

The generated package format uses a single `.xstk/` directory per imported
source stack.

## Package Root

```text
StackName.xstk/
  project.json
  stack_-1.json
  stylesheet_<STBL id>.css
```

`project.json` is the package index. It should capture source metadata, package
and importer version fields, the known block list, warnings, and references to
generated outputs.

`stack_-1.json` is the parsed stack-level object. It should include the stack
name, card size, stack script, list/font/style table IDs, layer references,
version information, protection flags, and raw or unknown fields where parsing
is incomplete.

`stylesheet_<STBL id>.css` is generated from the stack style table. For stacks
with missing style tables, such as HyperBBS stacks missing `STBL` ID `0`, the
package should include an empty fallback stylesheet and warnings in
`project.json`.

## Cards, Backgrounds, And Shared Structures

```text
StackName.xstk/
  background_<id>.json
  card_<id>.json
  master_-1.json
  pagesetup_<id>.json
  printsettings.json
  reporttemplate_<id>.json
```

Each `card_<id>.json` and `background_<id>.json` file can include parsed parts,
contents, scripts, geometry, style references, icons, and raw or unknown fields
where the block format is only partially understood.

`master_-1.json` represents parsed `MAST` data when present. Page setup,
print settings, and report template files represent `PRNT`, `PRST`, and `PRFT`
blocks respectively.

## Bitmap And Pattern Outputs

```text
StackName.xstk/
  PAT_1.pbm
  ...
  PAT_40.pbm
  BMAP_<id>.pbm
```

`PAT_*.pbm` files are the 40 stack patterns decoded from `STAK`.

`BMAP_<id>.pbm` files are decoded WOBA bitmap blocks. If the importer is run in
raw graphics mode instead of decoded bitmap mode, expect raw bitmap block
exports:

```text
StackName.xstk/
  BMAP_<id>.raw
```

## Raw Block Exports

When `--dumprawblocks` is enabled, the package can include raw block payloads:

```text
StackName.xstk/
  STAK_-1.data
  LIST_<id>.data
  FTBL_<id>.data
  STBL_<id>.data
  BKGD_<id>.data
  CARD_<id>.data
  PAGE_<id>.data
  MAST_-1.data
  PRNT_<id>.data
  PRST_<id>.data
  PRFT_<id>.data
  <unknown block>_<id>.data
```

Raw block exports are provenance-bearing evidence. Treat them as source
material for reverse engineering rather than derived presentation assets.

## Resource Disassembly

Once default resource disassembly is enabled, packages with external resources
should include a `resource-disassembly/` directory:

```text
StackName.xstk/
  resource-disassembly/
    resource-disassembly.provenance.json
    resource_dasm.log
    <StackName>_XCMD_<id>_<name>.txt
    <StackName>_XFCN_<id>_<name>.txt
```

The `.txt` files are 68K assembly listings produced by `resource_dasm`.

Examples:

```text
resource-disassembly/PLTE & XCMD Stack_XCMD_2367_ScrollControl.txt
resource-disassembly/PLTE & XCMD Stack_XFCN_4901_CreateMenu.txt
```

The portable importer does not fully parse Mac resource forks itself today.
`resource_dasm` is the practical path for XCMD/XFCN disassembly, while Hype
runtime compatibility remains based on explicit Swift emulators rather than
executing classic native resources.

## Future Resource-Derived Outputs

The docs and corpus suggest these resource exports may appear once resource
handling is broadened:

```text
StackName.xstk/
  resources/
    ICON_<id>...
    PICT_<id>...
    CURS_<id>...
    snd_<id>...
    XCMD_<id>.data
    XFCN_<id>.data
    xcmd_<id>.data
    xfcn_<id>.data
```

These files are expected to preserve or convert classic Mac resources without
executing native external code. Binary resource exports should retain enough
metadata to connect them back to resource IDs, names, types, and source forks.

## Generated Run Indexes

Importer run directories index package contents and extracted evidence outside
the `.xstk/` package:

```text
import-runs/<run-id>/
  run.db
  output-files.tsv
  embedded-files.tsv
  binary-chunks.tsv
  format-gaps.tsv
  stack-statistics.tsv
  resource reports
  XCMD-XFCN reports
```

`output-files.tsv` should identify generated package outputs. `embedded-files.tsv`
and `binary-chunks.tsv` should track extracted embedded payloads and binary
segments. `format-gaps.tsv` records unsupported, unknown, or partially parsed
format areas. `stack-statistics.tsv` captures summary counts useful for corpus
analysis.

## Complete Import Expectation

For a complete single-stack import, expect the `.xstk` package to include:

- `project.json`.
- `stack_-1.json`.
- All parsed `card_<id>.json` and `background_<id>.json` files.
- Shared structure files such as `master_-1.json`, page setup, print settings,
  and report templates when present.
- All decoded `PAT_*.pbm` and `BMAP_<id>.pbm` bitmap outputs, or raw `BMAP`
  outputs when raw graphics mode is selected.
- A stylesheet generated from `STBL`, or an empty fallback stylesheet plus
  warnings when the style table is missing.
- Resource disassembly outputs for any `XCMD` or `XFCN` resources once the
  default-on disassembly behavior is active.
- Provenance and log files for generated conversions.

The run directory should separately include indexes and reports that describe
the package contents, binary chunks, format gaps, stack statistics, and
resource/XCMD/XFCN outputs generated during the import.
