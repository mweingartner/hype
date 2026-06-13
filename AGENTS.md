# AGENTS.md

Repository-level instructions for agentic coding harnesses working on Hype.

## Read First

- Start with `architecture.md` before substantive code changes. It is the product and runtime architecture source of truth.
- Read and follow `decisions.md` for Hype product behavior, persistence, scripting, AI tooling, provider, and runtime guardrails. It is mandatory for all substantive changes.
- Use `README.md` for user-facing overview and setup context.
- Use `CONTRIBUTING.md` for contributor workflow and pull request documentation expectations.
- Use `HypeTalk-LLM-Context.md` and `Sources/HypeCore/AI/HypeTalkGuide.swift` when changing HypeTalk or AI model guidance.
- Treat `.hype` stack files as user documents. Do not stage or rewrite them unless the task explicitly requires it.

## Verification-First Workflow

Meaningful changes should follow this sequence:

1. Architect plan: identify the affected subsystem and expected behavior.
2. Security/safety review of the plan: identify persistence, network, keychain, file-system, script-execution, and AI-tool risks.
3. Build: make the smallest coherent implementation that preserves existing architecture.
4. Security/safety review of the build: check that the actual diff still matches the plan.
5. Test: add or update regression coverage, then run the narrowest relevant tests and a broader suite when shared runtime code changed.
   - **Parser / interpreter / chunk / file-format / network-protocol changes MUST keep the property/fuzz suite green** and, when they add a new language construct or format rule, extend it. See `Tests/HypeCoreTests/InterpreterFuzzTests.swift` (seeded grammar fuzzer + metamorphic relations). When the fuzzer finds a failure it prints the seed and source — add that seed to `regressionSeeds` to pin it.
   - Assert on **content**, never just existence (`#expect(x == 8)`, not `#expect(x != nil)`).
6. Gates: the change is not "done" until the automated gates are green — see **Automated Gates (CI)** below. Do not rely on "tests pass" reported by hand; the suite must actually run (a real, non-zero count) and the secret/SAST scans must be clean.
7. Deploy when user-facing macOS behavior changed: install `/Applications/Hype.app` and verify launch.

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

## Automated Gates (CI)

Three machine-enforced gates back the human/agent review. A change is not done
until they are green.

- **`secret-scan`** (`.github/workflows/secret-scan.yml`, hosted): gitleaks over
  the working tree (blocking) and history (advisory). Never commit secrets.
- **`sast`** (`.github/workflows/sast.yml`, hosted): Semgrep source-pattern
  analysis. Informational today; triage findings, then promote to blocking by
  removing `continue-on-error`. Deterministic backstop behind the security
  persona — do not treat the LLM security pass as sufficient on its own.
- **`ci`** (`.github/workflows/ci.yml`): `swift build` + full `swift test`
  (serial) + the interpreter fuzz suite + the watchOS kernel probe. Runs on a
  **self-hosted macOS runner** because the project pins a beta SDK (Swift 6.4 /
  macOS 27) that hosted runners lack. Activation is documented in the workflow
  header (register the runner, set repo variable `SELF_HOSTED_RUNNER_READY=true`,
  then require the `build-test-fuzz` check on `main`). Until then, run the gate
  locally before pushing.
- **`dependabot`** (`.github/dependabot.yml`): weekly SwiftPM + Actions updates
  and CVE alerts in the Security tab.

Run the interpreter fuzz/property suite locally:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift test --no-parallel --filter InterpreterFuzzNoCrashTests --filter InterpreterMetamorphicTests
```

The broader method these gates implement is written up in
`docs/Model-Paired-Development-Playbook.md`.

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
