# AGENTS.md

Repository-level instructions for agentic coding harnesses working on Hype.

## Read First

- Start with `architecture.md` before substantive code changes. It is the product and runtime architecture source of truth.
- Read and follow `decisions.md` for Hype product behavior, persistence, scripting, AI tooling, provider, and runtime guardrails. It is mandatory for all substantive changes.
- Use `README.md` for user-facing overview, setup, and contribution context.
- Use `HypeTalk-LLM-Context.md` and `Sources/HypeCore/AI/HypeTalkGuide.swift` when changing HypeTalk or AI model guidance.
- Treat `.hype` stack files as user documents. Do not stage or rewrite them unless the task explicitly requires it.

## Verification-First Workflow

Meaningful changes should follow this sequence:

1. Architect plan: identify the affected subsystem and expected behavior.
2. Security/safety review of the plan: identify persistence, network, keychain, file-system, script-execution, and AI-tool risks.
3. Build: make the smallest coherent implementation that preserves existing architecture.
4. Security/safety review of the build: check that the actual diff still matches the plan.
5. Test: add or update regression coverage, then run the narrowest relevant tests and a broader suite when shared runtime code changed.
6. Deploy when user-facing macOS behavior changed: install `/Applications/Hype.app` and verify launch.

For review-only tasks, do not edit files unless the user asks for implementation.

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
- `README.md`: setup, run/test commands, project overview.
- `docs/HyperCardImportAndXCMDCompatibility.md`: HyperCard import and XCMD/XFCN emulation rules.
- `TestStacks/PacmanAccessibilityTestbed.hype`: deterministic SpriteKit/accessibility smoke-test stack.
