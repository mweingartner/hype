# decisions.md

Product decisions and guardrails for how Hype should be built and behave.

These decisions are normative for agents and contributors. Read this file with
`architecture.md` before changing product behavior, persistence, scripting,
AI tooling, SpriteKit/Scene3D integration, provider integrations, or stack
document semantics.

## Product Architecture Guardrails

- Persist document state as value types in `HypeDocument`, `Stack`, `Background`, `Card`, `Part`, `SpriteAreaSpec`, and `SceneSpec`.
- Do not persist live AppKit, SpriteKit, SceneKit, AVFoundation, or network objects.
- Keep `SceneSpec` and `SpriteAreaSpec` as the source of truth for SpriteKit content; `SceneBridge` projects specs into live SpriteKit nodes.
- Route HypeTalk through `MessageDispatcher`, `Interpreter`, and `StackRuntime` rather than bypassing the message hierarchy.
- Preserve HyperCard-style message pass-up: part -> card -> background -> stack -> app, and scene/node -> sprite area -> card -> background -> stack -> app.
- Treat `.hype` stack files as self-contained user documents. User-created content should be persisted in the stack unless there is an explicit architecture-level reason to keep it external.

## HypeTalk Behavior Guardrails

- Generated, imported, or migrated scripts must parse through the existing parser and validator path before they are accepted as working output.
- Add parser/interpreter tests for new grammar, commands, properties, events, or legacy compatibility behavior.
- Do not silently swallow script errors. Route parse/runtime errors through existing logging and UI notification paths.
- Preserve HyperCard-style semantics where they exist in Hype: message dispatch, pass-up behavior, container ownership, and stack/card/background/object introspection.
- For legacy HyperCard compatibility, emulate behavior in Swift; never execute classic native XCMD/XFCN code.

## AI And Tooling Guardrails

- Keep AI authoring deterministic where tools exist. Prefer validated tools and templates over freehand raw script or node edits.
- Keep model prompts concise and source-grounded. Large catalogs should be discoverable through tools rather than always injected into the system prompt.
- Keep core deterministic creation offline. Optional OpenAI, Ollama, Meshy, web, or image-generation passes must not be required for baseline local template creation.
- Treat provider integrations as user-controlled side effects. Respect existing preferences, keychain handling, hostname allowlists, and stack-level opt-in gates.
- For stack context memory, use the stack-scoped AI context library and avoid secrets, API keys, credentials, or private tokens.
- Tool changes need schema coverage and execution-path tests.
- AI transactions should preserve preview/apply/rollback semantics where applicable.

## Runtime And Provider Guardrails

- Runtime behavior should be available through explicit provider abstractions so app-facing code can use real AppKit, audio, speech, AI, network, and file-system services while tests can use deterministic fakes.
- Browse-mode user actions should use the same runtime dispatch path as automated or scripted actions unless there is a documented reason to diverge.
- Network-backed or paid services must be optional, preference-gated, and safe to disable without breaking local stack creation or playback.
- Stack content should remain portable. External assets, generated media, context notes, and model-created content should be embedded or copied into the stack package when that is the expected user-facing behavior.

## References

- `architecture.md`: source of truth for architecture as built.
- `AGENTS.md`: agentic harness workflow, verification steps, test commands, deploy commands, and git hygiene.
- `HypeTalk-LLM-Context.md`: AI-facing HypeTalk guidance.
- `Sources/HypeCore/AI/HypeTalkGuide.swift`: in-app HypeTalk model guidance.
