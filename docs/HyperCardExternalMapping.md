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
