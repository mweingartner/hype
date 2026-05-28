# Contributing to Hype

Thanks for helping improve Hype. This project is a macOS-native Swift app with
a value-typed document model, SQLite-backed `.hype` packages, HypeTalk
scripting, SpriteKit rendering, and AI-assisted authoring tools. Small changes
are welcome, but product, persistence, scripting, AI, runtime, and UI behavior
all have architectural guardrails.

## Before You Start

- Read `architecture.md` for the current product and runtime architecture.
- Read `decisions.md` for product behavior, persistence, scripting, AI tooling,
  provider, and runtime guardrails.
- Follow `AGENTS.md` for verification workflow, safety checks, test commands,
  deployment steps, and git hygiene.
- Treat `.hype` stack files as user documents. Do not rewrite or stage them
  unless the change explicitly requires it.

## Development Workflow

1. Identify the affected subsystem and expected behavior.
2. Review safety implications before editing: persistence, network, keychain,
   file-system access, script execution, AI tools, and runtime side effects.
3. Make the smallest coherent implementation that fits the existing patterns.
4. Re-check the diff against the original plan and safety assumptions.
5. Add or update focused regression coverage.
6. Run the narrowest relevant tests, then a broader suite when shared runtime
   code changed.
7. For user-facing macOS behavior changes, build, deploy, and launch the app.

Use the project-local test wrapper when possible:

```bash
scripts/test.sh
scripts/test.sh --filter PlayCommandTests
```

If the shell has a stripped `PATH`, use:

```bash
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Codex.app/Contents/Resources /usr/bin/xcrun swift test --quiet
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Codex.app/Contents/Resources /usr/bin/xcrun swift test --filter PlayCommandTests
```

For app-facing behavior, also run:

```bash
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Codex.app/Contents/Resources ./script/build_and_run.sh --deploy
/usr/bin/open -n /Applications/Hype.app
```

## Pull Requests

Hype uses a standardized PR description so reviewers can quickly understand
what changed, why it changed, how it was implemented, and how it was verified.
GitHub will automatically load `.github/pull_request_template.md` for new PRs.

Use a concise, human-readable PR title that describes the product or code
change in imperative or descriptive form. Do not include agent/tool prefixes,
branch prefixes, usernames, ticket-only titles, or automation markers such as
`[codex]`, `codex/`, `wip`, or `generated`. Good titles name the affected
behavior, for example `Register imported paint layers as image assets`.

Every PR should cover:

- Summary: the overall effect of the change.
- Context: the business or technical reason for the change, including linked
  issues, design tickets, or prior discussion when available.
- Changes Made: the specific modules, behaviors, files, or APIs changed.
- Testing & Verification: automated tests, manual checks, and app launch or
  deployment checks when relevant.
- Screenshots / GIFs: visual proof for UI, layout, rendering, or interaction
  changes.
- Checklist: confirmation that tests, docs, safety review, and reviewer-facing
  prerequisites were handled.

Keep PRs focused. If a change mixes unrelated behavior, split it so each review
has a clear purpose and verification story.

## Documentation

Update documentation when behavior, setup, architecture, persistence, scripting,
AI tooling, or user-visible workflows change. In particular:

- Update `architecture.md` when architecture or subsystem boundaries change.
- Update `decisions.md` when a durable product behavior decision changes.
- Update `docs/SQLiteStackStorageDesign.md` for storage schema, document
  versioning, or migration behavior.
- Update `HypeTalk-LLM-Context.md` and
  `Sources/HypeCore/AI/HypeTalkGuide.swift` when HypeTalk or AI model guidance
  changes.

Breaking `.hype` document-shape changes must follow the migration workflow in
`AGENTS.md`; do not add silent decoder fallbacks.

## Git Hygiene

- Inspect `git status --short` before editing and before staging.
- Stage only intentional files with explicit paths.
- Do not revert unrelated user changes.
- Prefer `codex/<short-description>` branches when starting from `main`.
- Use terse imperative commit messages with a short body explaining why behavior
  changed.
