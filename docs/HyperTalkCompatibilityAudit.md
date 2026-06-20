---
type: audit
title: HyperTalk Compatibility Audit
description: Audit of HypeTalk vs classic HyperTalk — review phases, implemented remediation, and remaining intentional gaps.
updated: 2026-06-11
---

# HyperTalk Compatibility Audit

Source baseline: Apple, *HyperCard Script Language Guide*, especially the command
and function syntax summaries in Appendix H:
https://cancel.fm/stuff/share/HyperCard_Script_Language_Guide_1.pdf

HypeTalk is a HyperTalk descendant, not a byte-for-byte HyperCard runtime. The
compatibility goal is to preserve HyperCard author expectations where Hype has
equivalent stack, card, background, part, file, dialog, message, and expression
concepts while keeping Hype's modern extensions intact.

## Review Phases

1. Reference extraction
   - Use the Apple guide as the primary syntax source.
   - Classify commands, functions, properties, constants, system messages,
     object references, chunks, control flow, file I/O, dialogs, and external
     calls.
   - Keep source-derived examples in tests or compact docs, not in the always-on
     AI prompt.

2. Parser coverage
   - Add parser tests before remediation.
   - Cover classic spelling and reference aliases such as `cd` and `bkgnd`.
   - Cover Apple syntax forms such as `answer ... with reply1 or reply2`,
     `ask password clear ...`, `read from file ... at ... for/until ...`,
     `write ... to file ... at start/end/eof`, and `the abs of factor`.
   - Include Hype extensions in the same suite so new compatibility work cannot
     regress AI, SpriteKit, Meshy, AudioKit, MusicKit, speech, themes, or charts.

3. Runtime semantics
   - Prefer real functional tests over parse-only acceptance when behavior has a
     Hype equivalent.
   - Use `MessageDispatcher`, `Interpreter`, and sandboxed providers; never
     bypass the message hierarchy or file-security abstractions.
   - Use [`LegacyCardScriptLifecycleTestPlan.md`](LegacyCardScriptLifecycleTestPlan.md)
     for open/close/idle lifecycle parity across edit mode, runtime/Browse mode,
     imported stacks, and `lockMessages`.
   - Verify `it` semantics: `get`, `ask`, `answer`, `read`, request/reply, and
     explicit `put ... into it` set `it`; ordinary `put ... into/after/before`
     another container must not clobber the current `it`.

4. Safe compatibility shims
   - Implement legacy forms as AST/runtime features when Hype can safely model
     them.
   - Route XCMD/XFCN-style calls through `HyperCardExternalRegistry`.
   - Never execute original 68K/PPC native external code in process.

5. Gaps and intentional differences
   - Classic native external resources are preserved and reported, not executed.
   - Hype's `read from file` supports `at`, `for`, and `until` against a
     sandboxed whole-file read. Classic HyperCard's open-file cursor is not a
     first-class persisted runtime concept yet.
   - Classic UI/window/menu commands with no modern Hype equivalent may parse as
     safe no-ops or registry calls until a specific Hype behavior is defined.

6. Regression workflow
   - Run `scripts/test.sh --filter HyperTalkReferenceCompatibilityTests` for the
     source-derived compatibility suite.
   - Run `ScriptTests`, `ComprehensiveScriptTests`, `Phase4FileAccessTests`,
     `PlayCommandTests`, `HypeTalkScriptValidatorTests`, `CheckScriptToolTests`,
     `HypeTalkAITests`, and extension-specific HypeTalk suites after parser or
     interpreter changes.
   - Run the full suite before merging shared HypeTalk runtime work.

## Current Implemented Remediation

- Added `HyperTalkReferenceCompatibilityTests` with parser and runtime coverage
  for the Apple-guide command/function families plus Hype extensions.
- Added lexer aliases for `cd` and `bkgnd`.
- Added parser support for classic `ask password clear`, `ask file ... with
  default`, `answer program`, and multi-button `answer ... with ... or ...`
  forms.
- Added bounded `read from file` syntax for `at`, `for`, `until`, `eof`, `end`,
  `return`, `tab`, `space`, and `formFeed`-style constants.
- Added `write ... to file ... at start/end/eof` and numeric-offset insertion.
- Added Apple-guide function syntax such as `the abs of -5`, `the sqrt of 16`,
  `the length of "hello"`, and `the charToNum of "A"` without stealing Hype
  object properties such as `the value of data point ...`.
- Added classic `arrowKey` command behavior for left/right card navigation and
  parser acceptance for common keyboard-message commands.
- Corrected `put` semantics so writing to fields, buttons, properties, or scoped
  containers no longer clobbers `it`.
- Implemented chunk-destination `put` writes: `put <value> into/before/after
  <chunk> of <container>` now routes through `ChunkWriter`, which reads the
  container, applies the addressed sub-string replacement with classic
  HyperCard-compatible padding (items padded with commas, lines with newlines),
  and writes the result back. Supports char/word/item/line × `into`/`before`/
  `after`, numeric indices, ordinals (`first`, `last`, `middle`, etc.), and
  ranges. Read/write addressing is symmetric: any chunk expression valid in `get`
  is equally valid as a `put` destination. `it` is preserved across chunk writes.
  Unknown put targets raise a `ScriptError` routed through the normal error
  pipeline instead of silently writing to `it`.
- Custom-command `return` surfaces the value via `the result` in the caller and
  never writes the caller's `it`. `say`, `type`, and `choose` likewise leave
  `it` unchanged.

### Classic fidelity pass (2026-06-11)

Covered by `Tests/HypeCoreTests/Phase1FidelityTests.swift`.

- **Comparison type model.** `<`, `>`, `<=`, `>=`, `is`, `is not`, `=`, `<>` now
  follow HyperCard's rule: when *both* operands parse as numbers they compare
  numerically, otherwise they compare as case-insensitive text. A single
  `compare(...)` / `compareValues(...)` helper is the one place this rule lives,
  so `"10" > "9"` is true (numeric) while `"apple" < "banana"` is true (lexical).
- **Negation via number formatting.** Unary minus routes through `formatNumber`
  so `- -5` yields `5` and `-3.50` normalizes like every other numeric result.
  (`--x` remains a comment, per HyperTalk.)
- **`value()` / `the value of`.** Evaluates its argument as a HyperTalk
  expression (`value("2 * (3+1)")` → `8`); a bare identifier that is not a
  defined variable degrades to its literal text rather than empty, and dynamic
  evaluation is gated by the same recursion-depth and byte-size caps as `do`.
- **The message box.** `put X into the message box` / `msg` / `message`, and
  reading it back, persist through `__messagebox` in script globals (the key is
  stored lowercased so it survives `Environment` global-key normalization).
- **`the itemDelimiter`.** Honored by every item chunk read and write through
  `ChunkWriter`; classic HyperCard resets it to `,` at each top-level dispatch.
- **`the target` vs `me`.** `MessageDispatcher` threads the original target id
  through the handler chain so `the target` reports the part that first received
  the message even after `pass`, while `me` stays the current handler's object.
- **`find`, `sort`, and `repeat` forms.** Added `find`/`find chars`/`find
  word`/`find whole`/`find string`, `sort lines/items of <container>` with
  ascending/descending and text/numeric/international styles, and
  `repeat with i = N down to M` plus `repeat for each line/item/word ... in`.

## Remaining Work Items

- Decide whether to model a classic open-file cursor for `open file` / repeated
  `read from file` loops. Current bounded reads are deterministic whole-file
  slices through the sandbox provider.
- Expand safe native replacements for high-value XCMD/XFCN families discovered
  during real stack imports.
- Build a property-by-property compatibility matrix from Appendix I against
  Hype's current stack/card/background/part/scene-node property surface.
- Add behavior-level tests for more classic menu/window/printing commands once
  Hype defines modern equivalents.
