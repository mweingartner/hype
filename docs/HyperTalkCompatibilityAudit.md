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
