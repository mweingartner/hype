# Hype

Hype is a macOS-native visual authoring environment inspired by HyperCard. It
combines stacks, cards, backgrounds, and scriptable parts with a modern SwiftUI
and SpriteKit canvas, a HyperTalk-style language called HypeTalk, SQLite-backed
documents, and local-first AI-assisted authoring. Hype preserves HyperCard's
approachable authoring model; it is not a classic HyperCard runtime emulator.

## Highlights

- **Visual stack authoring:** compose cards from buttons, fields, media,
  drawing, charts, maps, web content, 3D scenes, and SpriteKit-backed parts.
- **HypeTalk:** automate parts and cards with message passing, handlers,
  expressions, asynchronous runtime operations, and a headless CLI.
- **Interactive scenes and games:** create persistent SpriteKit scene graphs or
  compile declarative `GameRecipe` values into scenes and validated HypeTalk.
- **Portable documents:** save stacks as SQLite-backed `.hype` packages with
  embedded assets, search data, and diagnostics.
- **Safe HyperCard import:** recover stack structure, scripts, paint layers, and
  resources without executing native XCMD or XFCN binaries.
- **AI-assisted editing:** use a local Ollama model by default, or explicitly
  configure another local or hosted provider. Proposed document mutations use
  preview/apply transaction boundaries.
- **Target-aware export:** generate runtime projects for supported Apple and web
  targets, with capability checks that reflect each target's available parts
  and runtime services.

## Quick start

### Requirements

- macOS 15 or later for the Hype authoring app
- Swift 6 and the Apple developer tools required by `Package.swift`
- Git

The package also declares iOS 17, tvOS 16, and watchOS 10 so consumers can
build supported `HypeCore` subsets and generated runtimes. That declaration
does not make the macOS authoring application available on those platforms.

### Build and run

```bash
git clone https://github.com/mweingartner/hype.git
cd hype
swift build
swift run Hype
```

To build a signed local app bundle, install it at `/Applications/Hype.app`, and
launch it, use the repository-supported deployment script:

```bash
script/build_and_run.sh --deploy
open -n /Applications/Hype.app
```

The script stops a running Hype process, builds the package, assembles
`dist/Hype.app`, signs it with a local development identity, and replaces the
installed app. It may create and import a local development signing identity
into the login keychain on first use.

### Test

```bash
scripts/test.sh
```

Forward SwiftPM arguments for focused or serial runs:

```bash
scripts/test.sh --filter PlayCommandTests
scripts/test.sh --no-parallel
```

Install the tracked hooks once per checkout:

```bash
scripts/install-git-hooks.sh
```

The local pre-push hook runs the repository's build and test gate for updates
to `main`. This is the enforced project gate; the repository does not rely on a
GitHub-hosted build/test workflow for the pinned local toolchain.

### Optional AI and network services

Hype's baseline authoring, documents, HypeTalk, and tests do not require a
hosted AI account. AI providers are selected in the app's settings:

- **Ollama** is the local-first authoring default and talks to a locally
  configured Ollama service.
- **llama-swap and other OpenAI-compatible endpoints** are optional and use
  their configured endpoint; optional credentials are stored in Keychain.
- **OpenAI** text, image, transcription, and speech features are hosted and
  send request content to OpenAI only after the user configures the provider
  and its Keychain credential.
- **Meshy.ai** generation, rigging, remeshing, and retexturing are hosted,
  potentially billable operations. They require both a Keychain API key and
  explicit enablement on the current stack.

Review the provider and network guardrails in
[`decisions.md`](decisions.md) before enabling external services.

## How Hype works

### Stacks, cards, backgrounds, and parts

A `HypeDocument` is a value-typed document graph. Its stack owns cards and
shared backgrounds; cards and backgrounds own parts. Parts provide the familiar
authoring surface—controls, text, media, paint, and richer framework-backed
views—while UUID-based identity keeps references stable across editing and
persistence.

The macOS app hosts documents with SwiftUI `DocumentGroup`. Only stack document
windows persist launch geometry, keyed by the stack's canonical file path;
auxiliary windows do not persist launch geometry. Hype reopens at most the last
stack recorded by its app-local launch state.

### HypeTalk

HypeTalk is a hand-written lexer, parser, and interpreter with HyperCard-style
message dispatch from part to card to background to stack to application. In
browse mode, `StackRuntime` owns asynchronous continuations, AI work, network
requests, listeners, and callbacks so explicitly suspending commands do not
block the UI or reorder handlers accidentally.

Run a script without the app through the `hypetalk` executable:

```bash
swift run hypetalk --help
```

Language compatibility and known gaps are documented in
[`docs/HyperTalkCompatibilityAudit.md`](docs/HyperTalkCompatibilityAudit.md).

### SpriteKit and GameRecipe

Cards use SpriteKit as an interaction and rendering substrate. Sprite areas can
host persistent scenes with sprites, physics, particles, tile maps, cameras,
and behavior-driven nodes. `GameRecipe` provides a higher-level declarative
model for entities, roles, rules, state, controls, and art roles; its compiler
produces a deterministic scene specification and validated HypeTalk.

### Documents and persistence

`.hype` documents are SQLite-backed packages. The storage layer persists the
document graph, scripts, assets, and search indexes and applies explicit schema
and migration rules. Provider credentials are not stored in stack documents.
See [`docs/SQLiteStackStorageDesign.md`](docs/SQLiteStackStorageDesign.md) for
the schema and migration contract.

### HyperCard import

Hype imports classic stack structure and supported resources through a bounded
conversion path. XCMD and XFCN resources can be inventoried and mapped to
reviewed Swift emulations, but native external code is never executed. Import
coverage and unsupported behavior are tracked in
[`docs/HyperCardImportAndXCMDCompatibility.md`](docs/HyperCardImportAndXCMDCompatibility.md)
and [`docs/ClassicHyperCardStackManifest.md`](docs/ClassicHyperCardStackManifest.md).

### Runtime export

The deployment subsystem emits target-specific runtime projects rather than
shipping the macOS editor itself. Availability varies by platform: generated
runtimes include only supported controls, frameworks, script features, and AI
policies. Non-macOS runtime AI defaults do not embed authoring-provider API keys
or local endpoints; supported Apple targets may use Apple's on-device
Foundation Models through the runtime provider layer.

## AI-assisted authoring

The AI chat surface supplies the selected model with a bounded tool catalog and
stack-scoped context. Tool calls are decoded into typed operations and applied
through the same document mutation coordinator used by the app. Mutating flows
support preview, apply, and rollback instead of granting a model arbitrary
filesystem or process access.

The AI Context Library can attach stack-scoped notes and approved files to a
session. Image generation, speech services, and 3D generation remain separate
optional provider operations with their own consent, credential, and egress
boundaries. Training and recorded model-evaluation artifacts live under
[`scripts/ai-training/`](scripts/ai-training/README.md); they are dated
experiments, not evergreen claims about current provider quality or reliability.

## Privacy, security, and trust boundaries

- Stack content stays local unless the user invokes or enables a feature whose
  configured provider requires network egress.
- Hosted provider keys are stored in macOS Keychain, not `.hype` documents.
- Stack networking is controlled by a persisted manifest and runtime policy;
  opening a document does not grant arbitrary outbound or listener access.
- HyperCard import treats legacy input as untrusted and never executes classic
  native external binaries.
- AI document edits use typed tools and transaction boundaries, but users should
  still inspect previews before applying consequential mutations.
- The debug bridge and MCP server are privileged developer automation surfaces.
  The app uses a permission-restricted local Unix socket rather than a TCP
  listener, and mutation calls remain subject to the app's mutation preference.
  Do not expose the socket or MCP process to untrusted clients.
- Exported runtimes have target-specific feature limits. Confirm the target
  capability report rather than assuming every macOS authoring feature exports.

Hype is development software. Keep backups of important stack documents and
review generated scripts, imported content, and network-enabled behavior before
using them with sensitive data.

## Developer and automation surfaces

SwiftPM exposes four products:

| Product | Purpose |
|---|---|
| `Hype` | macOS visual authoring application |
| `HypeCore` | document model, HypeTalk, persistence, rendering, AI, and runtime library |
| `hypetalk` | headless HypeTalk command-line runner |
| `HypePacmanTestbedBuilder` | generator for the Pac-Man regression stack |

Hype's local automation path deliberately separates protocol concerns:

```text
MCP client
  -> Tools/hype-mcp-server/bin/hype-mcp.js (stdio)
  -> Hype debug bridge (permission-restricted local Unix socket)
  -> active Hype.app document
```

The bridge must be enabled in Hype's preferences. The MCP process can discover
local Hype sessions and requires explicit attachment when more than one is
available. Setup, discovery, permissions, and mutation controls are documented
in [`docs/HypeDebugBridgeAndMCP.md`](docs/HypeDebugBridgeAndMCP.md).

## Project layout

```text
Sources/
  Hype/                         macOS app, AppKit/SwiftUI hosts, SpriteKit bridge
  HypeCore/                     models, storage, HypeTalk, AI, runtime and export
  HypeCLI/                      hypetalk command-line executable
  HypePacmanTestbedBuilder/     regression-stack generator
  CStackImport/                 classic stack-import system-library shim
Tests/
  HypeCoreTests/                core, storage, language and subsystem tests
  HypeTests/                    application-layer tests
  HypeCLITests/                 command-line tests
Tools/hype-mcp-server/          local stdio MCP bridge
docs/                           focused design, compatibility and operations docs
scripts/                        tests, gates, probes and AI-training tooling
script/build_and_run.sh         local app bundling and deployment
architecture.md                 implementation architecture and known gaps
decisions.md                    durable product and safety decisions
```

## Status and limitations

Hype is an actively developed authoring system. The repository contains working
implementations for the surfaces described above, but compatibility is not
universal:

- HypeTalk intentionally differs from classic HyperTalk where documented.
- Imported stacks may require script or layout remediation.
- Classic native externals require reviewed Swift emulation; they never run
  directly.
- Framework-backed parts and runtime services vary across export targets.
- Hosted AI and asset services depend on the selected provider, network access,
  account limits, and billing.
- The privileged debug/MCP surface is intended for trusted local development.

For implementation-level status and subsystem gaps, consult
[`architecture.md`](architecture.md). Benchmark results should be read from
their dated checked-in reports with the evaluation setup and observed versus
modeled metrics kept distinct.

## Documentation

- [`architecture.md`](architecture.md) — system architecture and subsystem map
- [`decisions.md`](decisions.md) — durable product and engineering guardrails
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — contribution and verification workflow
- [`AGENTS.md`](AGENTS.md) — model-paired development and repository gates
- [`docs/SQLiteStackStorageDesign.md`](docs/SQLiteStackStorageDesign.md) — document storage
- [`docs/HyperTalkCompatibilityAudit.md`](docs/HyperTalkCompatibilityAudit.md) — language compatibility
- [`docs/HyperCardImportAndXCMDCompatibility.md`](docs/HyperCardImportAndXCMDCompatibility.md) — import and external-command policy
- [`docs/HypeDebugBridgeAndMCP.md`](docs/HypeDebugBridgeAndMCP.md) — local automation boundary
- [`docs/AppleFrameworksRoadmap.md`](docs/AppleFrameworksRoadmap.md) — framework-part status and roadmap

## Contributing

Read [`CONTRIBUTING.md`](CONTRIBUTING.md), [`architecture.md`](architecture.md),
[`decisions.md`](decisions.md), and [`AGENTS.md`](AGENTS.md) before changing
behavior. Use the repository's model-paired development gates for non-trivial
work, add focused coverage with the implementation, run the full required test
gate, and stage only intentional files.

## License

Hype is available under the [MIT License](LICENSE). Copyright © 2026 Michael
Weingartner.
