---
type: workflow
title: Hype — Agent Workflow
description: Repository-level workflow for agentic coding harnesses — read-first docs, proportionate verification, the local test gate, and git hygiene.
updated: 2026-10-24
---

# AGENTS.md

Repository-level instructions for agentic coding harnesses working on Hype.

## Read First

- Start with `architecture.md` before substantive code changes. It is the product and runtime architecture source of truth.
- Read and follow `decisions.md` for Hype product behavior, persistence, scripting, AI tooling, provider, and runtime guardrails. It is mandatory for all substantive changes.
- Use `README.md` for user-facing overview and setup context.
- Use `CONTRIBUTING.md` for contributor workflow and pull request documentation expectations.
- Use `HypeTalk-LLM-Context.md` and `Sources/HypeCore/AI/HypeTalkGuide.swift` when changing HypeTalk or AI model guidance.
- Treat `.hype` stack files as user documents. Do not stage or rewrite them unless the task explicitly requires it.

## Doc Conventions

Durable docs (this file, `architecture.md`, `decisions.md`, the reference and
`docs/` audit/baseline/guide files) carry a small YAML frontmatter block:

```yaml
---
type: architecture | decisions | workflow | reference | audit | baseline | guide
title: <human title>
description: <one-line summary used to judge relevance / for recall>
updated: YYYY-MM-DD   # last *content* change — bump it when you materially edit
---
```

This mirrors the auto-memory format and the emerging Open Knowledge Format (OKF)
convention; it makes docs queryable and gives a staleness signal. When you
materially change a doc, bump its `updated`. Use **standard relative markdown
links** between docs (e.g. `[decisions](decisions.md)`), not `[[wikilinks]]`, so
links resolve on GitHub and in any tool. (The auto-memory store keeps `[[name]]`
links — that is the memory system's documented format, intentionally unchanged.)

## Development Workflow

Use the agent's normal design and implementation judgment. Scale planning and
verification to the change's uncertainty, consequences, and reversibility.

1. Establish the intended behavior, inspect the owning code, and choose the
   smallest coherent change. For consequential choices, document assumptions,
   acceptance examples, and material tradeoffs.
2. Review security and privacy boundaries before and after implementation.
3. Add meaningful regression coverage and run the narrowest relevant tests.
   Run broader tests when shared code changes. Parser, interpreter, chunk,
   file-format, and network-protocol changes must keep the fuzz/property suite
   green; extend it for new language constructs or format rules. Assert on
   content rather than existence.
4. Inspect user-visible changes in the running app, including loading, failure,
   keyboard, and accessibility states as applicable.
5. Update relevant documentation, then build and install the release in
   `/Applications/Hype.app` using `script/build_and_run.sh --deploy`. Launch
   the installed app and verify the real target. Skip installation only when
   the change produces nothing installable.

Report actual commands, test counts, failures, and remaining uncertainty. Never
claim tests ran when they did not, bypass a failing hook, or commit secrets.
For review-only tasks, do not edit files unless the user asks for implementation.

## Status Notifications

For substantive work, post concise status updates to the shared ntfy topic:
`https://ntfy.sh/hype-train-555`.

Send an update when work starts, when a meaningful milestone completes, when a
blocker needs attention, and when the task is done. Keep messages short and
actionable. Emoji and Markdown formatting are allowed when they make the action
or status easier to scan. Favor coordination updates and significant results in
testing, feature work, bug fixes, and polish progress. Do not post updates that
are only about local-facing test mechanics or routine command execution unless
the result changes project coordination or needs attention. Do not include
secrets, tokens, private user data, stack contents, or large diffs in ntfy
messages.

Example:

```bash
curl -d "✅ **Hype:** finished PR template cleanup; PR #20 updated" https://ntfy.sh/hype-train-555
```

## Document Breaking Changes

When a change breaks persisted `.hype` document shape, follow the versioned
migration workflow instead of adding silent decoder fallbacks:

1. Read the persistence sections in `architecture.md`, `decisions.md`, and
   `docs/SQLiteStackStorageDesign.md`.
2. Bump `HypeDocument.currentDocumentVersion`.
3. Add an incremental migration hook in `HypeSQLiteStackStore` that migrates old
   SQLite payloads before model decoding.
4. Store the new version in both `manifest.json.documentVersion` and
   `document_values.documentVersion`.
5. Add tests that save or synthesize an older package and prove load/search or
   validation migrates it on a temporary copy.
6. Update `architecture.md`, `decisions.md`, and
   `docs/SQLiteStackStorageDesign.md` with the version and migration behavior.

Migration hooks must not rewrite user `.hype` packages during load. The source
package changes only when the user explicitly saves.

## Product Decisions And Guardrails

`decisions.md` owns durable guidance for how Hype should behave. Do not duplicate
those product decisions here; keep this file focused on agent workflow,
verification, testing, deployment, and git hygiene.

## Testing Commands

Use the project-local wrappers when possible:

```bash
scripts/test.sh
scripts/test.sh --filter PlayCommandTests
```

If the shell has a stripped `PATH`, use:

```bash
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Codex.app/Contents/Resources /usr/bin/xcrun swift test --quiet
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Codex.app/Contents/Resources /usr/bin/xcrun swift test --filter PlayCommandTests
```

For app-facing changes, also build and deploy:

```bash
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Codex.app/Contents/Resources ./script/build_and_run.sh --deploy
/usr/bin/open -n /Applications/Hype.app
```

## Interpreter Fuzz / Property Suite

`Tests/HypeCoreTests/InterpreterFuzzTests.swift` is a seeded grammar fuzzer over
generated HypeTalk handlers plus oracle-free metamorphic relations. Parser /
interpreter / chunk / file-format / protocol changes must keep it green and
extend it for new constructs. Run it locally:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --no-parallel --filter InterpreterFuzzNoCrashTests --filter InterpreterMetamorphicTests
```

## Local Build/Test Gate (pre-push hook)

A tracked pre-push hook enforces the build/test gate locally — the machine
runs it, not the agent's word. Install once per clone:

```bash
scripts/install-git-hooks.sh        # sets core.hooksPath = .githooks
```

`.githooks/pre-push` runs `swift test --no-parallel --filter HypeCoreTests
--filter HypeCLITests` before any push that updates `main`, and aborts the push
if it fails. That **builds every target** (incl. the Hype app, so a compile
break anywhere fails the gate) and **runs** the interpreter, fuzz/property, and
CLI suites. The AppKit `HypeTests` target is excluded from execution because it
crashes under `--no-parallel` in a headless run (and the parallel runner stalls
on HypeCoreTests in this toolchain) — validate `HypeTests` by launching
`/Applications/Hype.app`. Pushes to other branches are not delayed. Bypass only
when justified (e.g. a docs-only push):

```bash
git push --no-verify           # or:  HYPE_SKIP_PREPUSH=1 git push
```

This replaces the (removed) GitHub CI build/test gate — the project pins a beta
toolchain hosted runners can't build, so enforcement lives locally.

## Git Hygiene

- Inspect `git status --short` before editing and before staging.
- Stage only intentional files. Use explicit paths when the worktree contains stack documents or unrelated user edits.
- Never revert user changes unless explicitly asked.
- Prefer `codex/<short-description>` branches when starting from `main`.
- Commit messages should be terse and imperative, with enough body text to explain why behavior changed.
- Push the branch and open a draft PR unless the user explicitly asks for direct main-branch commits.

## Useful References

- `decisions.md`: product behavior guardrails and durable build decisions.
- `architecture.md`: full architecture, subsystem map, persistence/runtime boundaries, feature gaps.
- `CONTRIBUTING.md`: contributor workflow, PR documentation, verification expectations, and git hygiene.
- `.github/pull_request_template.md`: GitHub PR template with Summary, Context, Changes Made, Testing & Verification, Screenshots / GIFs, and Checklist sections.
- `docs/SQLiteStackStorageDesign.md`: SQLite package schema, document versioning, and migration workflow.
- `README.md`: setup, run/test commands, project overview.
- `docs/HyperCardImportAndXCMDCompatibility.md`: HyperCard import and XCMD/XFCN emulation rules.
- `TestStacks/PacmanAccessibilityTestbed.hype`: deterministic SpriteKit/accessibility smoke-test stack.
