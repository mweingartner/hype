# decisions.md

Product decisions and guardrails for how Hype should be built and behave.

These decisions are normative for agents and contributors. Read this file with
`architecture.md` before changing product behavior, persistence, scripting,
AI tooling, SpriteKit/Scene3D integration, provider integrations, or stack
document semantics.

## Product Architecture Guardrails

- Persist document state in self-contained SQLite-backed `.hype` packages. The runtime model remains value typed through `HypeDocument`, `Stack`, `Background`, `Card`, `Part`, `SpriteAreaSpec`, and `SceneSpec`.
- Do not persist live AppKit, SpriteKit, SceneKit, AVFoundation, AudioKit, or network objects.
- New stacks must ask for target platforms before normal authoring continues. The default selection is macOS, but iPhone, iPad, and tvOS are first-class selectable targets; iPad is not treated as just a large iPhone.
- The object palette must show only creation controls that work across every selected target platform. If a target runtime lacks a safe implementation for a control, hide that control from the creation panel rather than letting the user build a non-deployable stack by accident.
- Target-device emulation is an authoring view over the same document. Edits made while emulating are immediate normal document edits and autosave/undo should treat them like any other edit.
- Target layout behavior must remain declarative. Use target profiles, `layoutPolicy`, explicit constraints, and `LayoutResolver`; do not persist live platform view state or bake casual drag snapping into durable responsive constraints.
- AI-created card layouts must use target-aware HIG layout tools where possible. Prefer safe-area constraints, selected-target validation, and deterministic HIG arrangements over freehand coordinate sequences.
- Deployed stacks are runtime-only. Standalone exported apps must not expose edit mode, object palettes, property inspectors, script editor windows, AI/debug panels, or authoring-only preferences unless a future explicit runtime-authoring product mode is designed.
- Runtime export must validate the actual stack contents against the selected target platform. If existing parts are unsupported on a target, fail before package generation with actionable part names and reasons instead of producing a broken runtime artifact.
- Runtime export artifacts must be self-contained and diagnosable: include the embedded SQLite `.hype` package, runtime manifest, shell metadata, target app project files, runtime source dependencies needed for standalone builds, and entitlement/capability requirements; do not include API keys, local model endpoints, authoring preferences, temp files, or absolute user paths.
- HyperCard-compatible `userLevel` is stack state, not a local preference: 1 Browsing, 2 Typing, 3 Painting, 4 Authoring, 5 Scripting. It gates Hype's authoring UI, menus, script-editor access, inline field editing, paint tools, and AI authoring surfaces, but it is not a security boundary and must not replace dedicated file, network, AI-context, keychain, or debug/MCP permission checks.
- Hype intentionally keeps card/background creation, deletion, and layout mutation at Authoring or higher even though classic HyperCard allowed some card operations at Typing. In Hype, Typing means end-user text entry in unlocked fields only.
- Controls that render local media must store deployment resources in the stack, not as raw external file dependencies. PDF, video, Scene3D model, and recorded-audio file references should be copied into stack-owned assets or embedded data before runtime export. Webpage controls are the explicit exception because live web content is their purpose. Do not fetch remote media implicitly during export; require an explicit import/generation step instead.
- The target-device catalog should track Apple's currently shipping iPhone and iPad form factors and derive logical profile sizes from Xcode CoreSimulator metadata where available. Generic iPhone/iPad profiles may remain as authoring conveniences, but current device profiles must be available for emulation and regression coverage.
- Simulator testing is an authoring convenience over runtime export. It must reuse the same deployment validation and self-contained runtime package builder, never mutate the source stack, and launch Xcode's Simulator through explicit `xcrun` / `open` process arguments rather than shell-interpolated commands.
- Deployed non-macOS runtime scripts must prefer Apple built-in AI support through the runtime AI provider layer where available. iPhone and iPad default to Apple Foundation Models; tvOS must degrade gracefully until Apple exposes a supported on-device language-model runtime there. Do not embed OpenAI/Ollama/local-model endpoints or API keys in deployed non-macOS runtime defaults.
- Persist AudioKit-backed music as declarative patterns/tracks/assets in the stack; reconstruct `AudioEngine`, samplers, players, and playback tasks at runtime through providers.
- Keep `SceneSpec` and `SpriteAreaSpec` as the source of truth for SpriteKit content; `SceneBridge` projects specs into live SpriteKit nodes.
- Route HypeTalk through `MessageDispatcher`, `Interpreter`, and `StackRuntime` rather than bypassing the message hierarchy.
- Preserve HyperCard-style message pass-up: part -> card -> background -> active stack -> used stack scripts -> app, and scene/node -> sprite area -> card -> background -> active stack -> used stack scripts -> app.
- Multi-stack navigation must resolve through persisted stack-library metadata and return explicit project-navigation targets; app routing opens only `.hype` documents and then performs local card selection, while single-stack card navigation remains local to the active `HypeDocument`.
- Treat `.hype` stack files as self-contained user documents. User-created content should be persisted in the stack unless there is an explicit architecture-level reason to keep it external.
- Keep SQLite storage diagnosable: core stack layout, scripts, assets, AI context, SpriteKit scenes/nodes, and search indexes should be inspectable through tables, indexes, and validation views.
- Breaking document-model changes must bump `HypeDocument.currentDocumentVersion`, write the new version into `manifest.json` and `document_values`, and add a forward migration hook in `HypeSQLiteStackStore` before any old payloads are decoded.
- Migrations run on a temporary database copy during load/search/validation. Opening an older stack must not rewrite the user's source package until the user explicitly saves it.

## HypeTalk Behavior Guardrails

- Generated, imported, or migrated scripts must parse through the existing parser and validator path before they are accepted as working output.
- Add parser/interpreter tests for new grammar, commands, properties, events, or legacy compatibility behavior.
- Do not silently swallow script errors. Route parse/runtime errors through existing logging and UI notification paths.
- Preserve HyperCard-style semantics where they exist in Hype: message dispatch, pass-up behavior, container ownership, and stack/card/background/object introspection.
- Preserve classic `it` semantics: commands such as `get`, `ask`, `answer`, `read`, request/reply, and explicit `put ... into it` may set `it`; ordinary `put ... into/after/before` another field, button, property, or scoped container must not clobber `it`.
- For legacy HyperCard compatibility, emulate behavior in Swift; never execute classic native XCMD/XFCN code.
- Legacy external emulators should expose explicit script-visible outcomes
  (`it`, `the result`, runtime globals, visual-effect intent, or document
  mutation) instead of hidden no-ops.

## AI And Tooling Guardrails

- Keep AI authoring deterministic where tools exist. Prefer validated tools and templates over freehand raw script or node edits.
- Keep model prompts concise and source-grounded. Large catalogs should be discoverable through tools rather than always injected into the system prompt.
- Expand AI context through explicit, auditable tools rather than by adding large dynamic catalogs, private libraries, or broad project data directly to the prompt window.
- External scripting references should be curated into source-attributed, Hype-specific tool guides and parser-tested patterns. Do not paste large raw reference material into every model prompt or treat classic HyperTalk behavior as implemented until Hype compatibility is verified.
- Keep core deterministic creation offline. Optional OpenAI, Ollama, Meshy, web, or image-generation passes must not be required for baseline local template creation.
- Treat provider integrations as user-controlled side effects. Respect existing preferences, keychain handling, hostname allowlists, and stack-level opt-in gates.
- Keep deployed-runtime AI tools separate from authoring tools. Runtime AI may read runtime-safe stack/card/object context by default; any side-effect tool must be explicitly allowlisted by stack runtime AI settings.
- For stack context memory, use the stack-scoped AI context library and avoid secrets, API keys, credentials, or private tokens.
- Tool changes need schema coverage and execution-path tests.
- AI transactions should preserve preview/apply/rollback semantics where applicable.

## Game Recipe Authoring Guardrails

- Game-authoring recipes compile through the deterministic `RecipeCompiler` to
  validated HypeTalk. The compiler is the single authoritative lowering path for
  both AI-driven and manual (Property Inspector) recipe authoring; the two paths
  must not diverge.
- Recipe-supplied strings (entity names, status messages, art-role names, HUD
  labels) must be sanitized through `sanitizedLiteral(...)` before interpolation
  into generated HypeTalk script. No recipe string should ever escape a string
  literal in generated code, regardless of what the AI or user provides.
- Generated scripts must pass the real Lexer + Parser validator gate before being
  stored in the document. An emitted script that fails to parse is replaced with
  a safe minimal fallback and a diagnostic is recorded; no invalid HypeTalk may
  reach the `SceneSpec` via the recipe path.
- `SpriteAreaSpec.recipe` is additive optional state. Its presence or absence
  must not require a document-version bump; decoders use `decodeIfPresent` so
  all existing `.hype` files continue to load with `recipe == nil`. `SceneSpec`
  remains the runtime source of truth; the recipe is an authoring and
  regeneration input only.
- Recipe authoring must honor user intent verbatim: entity names, scene size,
  and art-role bindings must be preserved through compilation without
  normalization or substitution. Genre presets are data starting points, not
  overrides; the user customizes the recipe, not patched scripts.
- `build_game` must fail closed on existing targets. If the requested sprite area
  already exists and was not started in the current recipe session, the tool must
  refuse rather than silently overwrite it with a default template.
- Consistent with the existing "intent outranks template defaults" and "fail
  closed" guardrails in the AI and SpriteKit tooling sections above.

## Runtime And Provider Guardrails

- Runtime behavior should be available through explicit provider abstractions so app-facing code can use real AppKit, audio, speech, AI, network, and file-system services while tests can use deterministic fakes.
- Browse-mode user actions should use the same runtime dispatch path as automated or scripted actions unless there is a documented reason to diverge.
- Network-backed or paid services must be optional, preference-gated, and safe to disable without breaking local stack creation or playback.
- Stack content should remain portable. External assets, generated media, context notes, and model-created content should be embedded or copied into the stack package when that is the expected user-facing behavior.

## References

- `architecture.md`: source of truth for architecture as built.
- `docs/SQLiteStackStorageDesign.md`: SQLite package storage schema and diagnostics.
- `AGENTS.md`: agentic harness workflow, verification steps, test commands, deploy commands, and git hygiene.
- `HypeTalk-LLM-Context.md`: AI-facing HypeTalk guidance.
- `Sources/HypeCore/AI/HypeTalkGuide.swift`: in-app HypeTalk model guidance.
