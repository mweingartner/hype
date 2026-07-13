# Design: Refresh the GitHub README from current repository evidence

## Context

`README.md` is already a substantial product reference (1,000+ lines) and was last materially changed at commit `a6c4098`. Since then, `main` has added or revised runtime-export hardening, the MPD workflow, deployment tooling, window restoration, and documentation/persona infrastructure. The current README contains useful detail, but it also contains high-drift assertions such as exact AI-tool counts, an approximately stated test count, dated model leaderboard results, implementation-status summaries, and commands whose continuing validity must be proven rather than assumed.

The root README is rendered by GitHub and serves multiple audiences: prospective users, local builders, contributors, security-conscious evaluators, and developers looking for subsystem references. It should optimize first for truthful orientation and successful onboarding, while deep architecture and compatibility inventories remain in their dedicated documents.

This is a documentation-only change. It does not alter Hype behavior, source, dependencies, storage, provider configuration, network access, or deployment artifacts.

## Goals / Non-Goals

### Goals

- Present a clear, polished explanation of Hype and its current shipped surface.
- Make the fastest supported path to prerequisites, build, test, install, and launch discoverable.
- Distinguish default local behavior from explicitly configured network-backed features.
- Base quantitative and status claims on reproducible repository evidence, with dates or provenance where appropriate.
- Keep GitHub links, anchors, code fences, tables, and relative paths valid.
- Direct readers to the authoritative architecture, decisions, compatibility, persistence, MCP, training, and contributing documents.
- Ensure the README accurately describes the current `main` candidate at the point it is committed.

### Non-Goals

- Changing production code, tests, scripts, package dependencies, application behavior, or release configuration.
- Inventing a product roadmap, marketing guarantees, support policy, or release version not present in the repository.
- Reproducing all of `architecture.md`, `decisions.md`, or specialized compatibility documents in the README.
- Re-running paid or network-backed AI benchmark suites solely to refresh prose; dated checked-in benchmark artifacts may be cited with explicit provenance and without presenting modeled retry probability as observed success.
- Publishing a GitHub release, changing repository settings, or altering the license.

## Evidence Model

The Builder shall classify README statements before writing them:

1. **Durable identity and architecture** — verify against `Package.swift`, `architecture.md`, `decisions.md`, and concrete source paths.
2. **Current capability** — require an implementation symbol/path plus relevant tests or a durable subsystem document. Describe opt-in, platform, and safety constraints alongside the capability.
3. **Commands and prerequisites** — verify the referenced script/file exists and execute safe local commands where the Test phase calls for them. Do not claim a command was run merely because it exists.
4. **Counts and benchmark results** — derive counts mechanically when possible. Otherwise identify the dated checked-in artifact and label the result as a recorded benchmark, not a timeless current fact. Approximate test counts are permitted only when paired with the exact command and dated run evidence; exact observed counts are preferred.
5. **Status and limitations** — reconcile with the current source and focused docs. Prefer explicit limitations over broad completeness claims.
6. **External-service behavior** — describe credentials, opt-in controls, egress, and cost/network implications from code and security/product guardrails. Avoid provider-performance endorsements unsupported by current reproducible evidence.

Repository files are primary evidence for what this checkout implements. External product or historical claims, if retained, need an original authoritative source link; otherwise they should be phrased narrowly or removed.

## README Information Architecture

The refreshed README should use this reader-first order, adapting headings only where the content reads more naturally:

1. **Hero and one-paragraph value proposition** — name Hype, macOS authoring focus, HyperCard inspiration, HypeTalk, and local-first AI without claiming classic runtime emulation.
2. **Current highlights** — a short, scannable set of differentiated implemented capabilities; move exhaustive type lists and subsystem internals lower or link outward.
3. **Quick start** — requirements, clone/build/run, install to `/Applications`, test commands, and optional services. Commands must be copyable from a clean checkout and match current scripts.
4. **How Hype works** — stacks/cards/backgrounds/parts, HypeTalk, SpriteKit/GameRecipe, SQLite `.hype` documents, import, target runtime export, and AI transactions at an architectural-summary level.
5. **Privacy, trust, and optional services** — local Ollama default, hosted provider opt-in, Keychain/API-key behavior, per-stack gates, safe HyperCard import, and the privileged local MCP/debug boundary. Link to `SECURITY.md` if one exists; if it does not, link only to actual authoritative documents and do not invent it.
6. **Developer and automation surfaces** — library/CLI/app products, MCP bridge, test workflow, and project layout.
7. **Status, limitations, and provenance** — use verified present-tense status; separate recorded benchmark results and known gaps from shipped functionality.
8. **Documentation, contributing, and license** — verified relative links and a concise contribution path.

The README may retain useful examples and tables, but each must serve onboarding or comprehension. Highly detailed inventories belong behind links when duplication increases drift risk.

## Exact File-Level Plan

### `README.md`

- Audit the entire file, not only the opening sections.
- Rewrite the opening and section order to implement the information architecture above.
- Reconcile platform declarations and products with `Package.swift` (macOS 15 authoring app; package declarations and runtime/export claims must be carefully distinguished).
- Reconcile application architecture and feature descriptions with `architecture.md`, `decisions.md`, and real source paths.
- Reconcile recent operational changes explicitly: MPD is now the documented gated workflow, deploy installs `/Applications/Hype.app`, the pre-push gate is local rather than GitHub-hosted CI, and stack document windows restore per canonical stack path while auxiliary windows do not persist launch geometry.
- Recompute or qualify volatile tool, test, prompt, preset, control, theme, and message counts. Prefer a durable qualitative phrase when a count is not central to user understanding.
- Preserve benchmark tables only if their source artifact, date/provenance, evaluation meaning, and observed-versus-modeled distinction are clear; otherwise link to the checked-in evaluation report.
- Verify build, run, test, install, MCP, and optional-provider commands against existing scripts and executables.
- Update the project tree to current high-level paths without attempting an exhaustive mirror of the repository.
- Add or strengthen a limitations/trust-boundaries section: classic native XCMD/XFCN code is never executed; cloud/provider and Meshy features are optional; MCP/debug is a privileged local automation boundary; exported runtimes have target-specific availability.
- Remove stale chronology, duplicated status narratives, and any assertion that cannot be traced to current repository evidence.
- Use GitHub-compatible relative Markdown links and descriptive link labels.

### OpenSpec artifacts

- Keep `proposal.md`, `specs/github-readme/spec.md`, `design.md`, and `tasks.md` as the durable written intent and gate evidence for the documentation refresh.
- No source or test file is expected to change.

## Verification Plan

### Documentation correctness

- Extract every local Markdown link and verify its target exists; manually verify heading fragments used by local anchors.
- Check Markdown structure for balanced fences, coherent heading levels, readable tables, and no absolute developer-specific filesystem links.
- Search the final README for volatile patterns (counts, percentages, “current”, “latest”, “all”, “full”, “complete”, platform versions) and map each occurrence to evidence or qualify/remove it.
- Compare `README.md` claims against `Package.swift`, `architecture.md`, `decisions.md`, `CONTRIBUTING.md`, `Sources/`, `Tests/`, `scripts/`, `script/`, and relevant `docs/` files.
- Inspect the rendered README on GitHub after push, or use a local GitHub-compatible renderer when available before push and then verify the actual GitHub page after push.

### Repository verification

- Run the Test-phase brief exactly. Because the change is documentation-only, no production regression is expected, but the repository’s configured MPD and git gates remain authoritative and must not be bypassed.
- Confirm `git diff --check` and inspect the full README diff.
- Before commit, confirm only intended documentation/process artifacts are staged and no `.hype` user documents, secrets, generated applications, build products, or local environment files are included.
- After push, confirm local `main`, `origin/main`, and GitHub’s default branch resolve to the same commit and the public README renders from that commit.

## Risk-to-Test Map

| Risk | Verification |
|---|---|
| A feature is described as shipped when it is partial, gated, or target-specific | Trace to source + tests + authoritative docs; state gates/limits adjacent to claim |
| Exact counts drift immediately | Derive mechanically or replace with qualitative wording; scan all numbers before sign-off |
| Benchmark probability is mistaken for observed reliability | Attribute to dated artifact and label modeled metrics; prefer linking over promotional summary |
| Setup instructions fail on a clean checkout | Verify files/options exist; run safe build/test commands in Test phase |
| GitHub links or anchors break | Automated local-link extraction plus post-push GitHub render inspection |
| Local-first language hides optional egress | Explicit provider matrix/trust section with opt-in and credential boundaries |
| README becomes an unmaintainable architecture duplicate | Summarize stable concepts and link to authoritative deep documents |
| Documentation-only work accidentally stages user or generated data | Explicit-path staging and staged-diff/secret checks |
| README claims validation that did not run | Report commands and observed counts separately from descriptive claims |
| README repeats removed GitHub CI enforcement | Describe the current local pre-push gate and avoid badges or wording that imply a hosted build/test check |
| Whole-tree secret scans traverse generated output or flag reviewed synthetic credential-shaped lifecycle fixtures | Extend the gitleaks default rules with anchored path allowlists for only `.build/`, `dist/`, `.hype-codesign/`, `.hype/visual-qa/`, and `scripts/ai-training/out/`; suppress only the exact reviewed fingerprints for the two synthetic Meshy lifecycle fixtures; prove generated fixtures are skipped while the same detector still fails on another tracked path |

## Decisions and Trade-offs

- **Evidence-first rewrite, not additive patching.** A whole-file audit is necessary because drift appears in the hero, highlights, detailed subsystem sections, status, commands, and contribution guidance. The trade-off is a larger documentation diff, mitigated by preserving accurate explanations and reviewing claim-by-claim.
- **Reader-first summary plus authoritative links.** This reduces duplicate detail and future drift. Some implementation depth leaves the landing page, but remains available in architecture and focused docs.
- **Qualitative durability over decorative precision.** Counts are retained only when they materially help and can be reproduced. This gives up impressive-looking numbers in favor of long-lived accuracy.
- **Repository evidence over web research for implementation facts.** The checkout is authoritative for shipped code. External links are used only for external historical/platform facts that remain in the README and can be supported by original sources.
- **Documentation-only deploy.** The change produces no different app binary. The MPD Deploy phase should follow its generated brief; if it identifies no installable change, it should record a documented N/A/readiness result only through supported MPD semantics, never by faking an app deployment.
- **Narrow generated-output scanner boundary.** The repository-level gitleaks
  configuration extends, rather than replaces, the default detector set. Its
  allowlist is path-only and anchored to five generated-output directories:
  `.build/`, `dist/`, `.hype-codesign/`, `.hype/visual-qa/`, and
  `scripts/ai-training/out/`. This
  keeps repeatable whole-tree scans from treating build or QA artifacts as
  source while deliberately leaving every other ignored directory and every
  filename/content pattern subject to the default rules. A disposable fixture
  test must show both exclusion and continued detection; no detector-shaped
  fixture belongs in the repository. The separate `.gitleaksignore` contains
  only two exact fingerprints for reviewed synthetic Meshy API-key lifecycle
  fixtures already committed in `HypeTests`; it does not suppress either rule
  elsewhere.

## Security Plan Review

**Verdict: PASS.** The proposed change is documentation-only and introduces no
new runtime capability, persistence format, dependency, credential flow, or
network operation. The security-sensitive output is nevertheless public and
executable by readers, so the review treated README prose, commands, links, and
embedded content as a publication and social-engineering boundary.

Reviewed trust surfaces:

- Hosted-provider and Meshy descriptions must identify opt-in egress, cost, and
  credential boundaries without exposing keys or implying that local-first
  operation prevents all network access.
- MCP/debug automation must remain described as a privileged, loopback-local
  development boundary, not a safe remotely exposed service.
- HyperCard stacks and legacy externals remain untrusted input; the README must
  distinguish structural import and supported Swift emulation from execution of
  native XCMD/XFCN binaries.
- Copyable onboarding commands must use repository-owned scripts or standard
  tool invocations and must not normalize verification bypass, remote
  script-piping, broad permissions, plaintext credentials, or non-loopback
  service exposure.
- Public Markdown must not leak local paths, usernames, private endpoints,
  stack contents, tokens, shell history, or machine state through prose,
  command output, images, badges, or link targets.
- External links and embedded assets are a supply-chain and tracking surface;
  retain only necessary authoritative HTTPS links and repository-owned media,
  without third-party tracking pixels or unreviewed remote badges.

The original conditions already covered evidence provenance, provider egress,
secret exclusion, legacy-code non-execution, explicit staging, hook enforcement,
and GitHub post-publication verification. Conditions 13-16 below close the
remaining command, automation, and remote-content publication gaps. Security
(code) must review the final README diff and secret-scan the staged content;
this plan-stage PASS does not approve the eventual prose.

## Conditions for Builder

1. Change only `README.md`, the narrowly scoped `.gitleaks.toml`, and the MPD/OpenSpec artifacts required by this change; do not modify production code, tests, dependencies, `.hype` documents, other repository settings, or generated build/install artifacts.
2. Treat every statement about current behavior as untrusted until it is traced to current source, tests, scripts, package configuration, or an authoritative durable repository document.
3. Do not retain an exact count, percentage, “latest/current” result, completeness claim, or platform-support claim without reproducible evidence and appropriate date/provenance; distinguish observed benchmark results from modeled retry probabilities.
4. Do not imply that local-first defaults eliminate all possible network egress. Name every described hosted/network-backed feature as optional and state its opt-in, credential, or per-stack boundary accurately.
5. Do not expose API keys, tokens, private endpoints, user document contents, absolute developer paths, machine-specific state, or other secrets in the README, evidence, commit, or notifications.
6. Do not state or imply that Hype executes legacy native HyperCard externals; preserve the explicit safe-import and Swift-emulation boundary.
7. Every command, filename, product, target, link, and path in the final README must exist and be checked against the final committed tree; use GitHub-compatible relative links.
8. The README must remain useful without optional AI providers: baseline build, authoring, HypeTalk, documents, and testing must not be presented as requiring OpenAI, Meshy, or another hosted service.
9. Preserve the MIT license attribution and avoid adding third-party logos, screenshots, quotations, or marketing assets without verified provenance and repository authorization.
10. Run the MPD-generated downstream briefs and machine-enforced git hooks exactly; never bypass a FAIL gate or commit/push around a hook.
11. Stage explicit paths only and inspect the staged diff for unrelated or user-owned changes before committing.
12. After push, verify the actual GitHub README, default-branch commit, and local/remote commit identity before declaring completion.
13. Do not add commands that pipe network responses into a shell, bypass TLS or git verification, disable hooks/tests, grant broad permissions, require credentials in command-line arguments, or expose a service beyond loopback. Any destructive or state-changing command must name its effect and use an existing repository-supported workflow.
14. Describe MCP/debug automation as privileged and loopback-local; do not provide instructions that bind it publicly, weaken its access controls, or imply untrusted clients may use it safely.
15. Use only necessary authoritative HTTPS external links and repository-owned images/assets. Do not add tracking pixels, unreviewed remote badges, URL-embedded identifiers, or externally hosted content that can leak a GitHub reader's visit.
16. Before publication, scan the complete README and staged diff for secrets and privacy leaks, including credentials, private endpoints, usernames, absolute paths, machine-specific output, shell history, and user `.hype` document content; Security (code) must inspect every copyable command and external URL.
17. The gitleaks configuration must extend the built-in defaults and may exempt
    only paths rooted at `.build/`, `dist/`, `.hype-codesign/`,
    `.hype/visual-qa/`, and `scripts/ai-training/out/`. The fingerprint ignore
    file may contain only
    `Tests/HypeTests/Generate3DSheetLifecycleTests.swift:generic-api-key:418`
    and
    `Tests/HypeTests/RigAndAnimateCoordinatorLifecycleTests.swift:generic-api-key:373`,
    the reviewed synthetic Meshy lifecycle fixtures. Do not add other detector,
    commit, regex, filename, fingerprint, or stopword exceptions. Validate with
    disposable files that a generated-path dummy finding is skipped, the
    reviewed repository scan is clean, and the same default detector still
    reports a dummy finding on another tracked path.

## Tester Evidence

**Verdict: PASS.** Independent documentation and repository testing completed
on 2026-07-13 against the actual `README.md`, scanner configuration, and
OpenSpec diff.

- Functional/error/boundary checks: all 22 Markdown links are repository-local
  and resolve; all named products, source/test directories, documents, scripts,
  commands, and documented options exist. Sixteen code-fence markers are
  balanced, heading levels are coherent, the product table is structurally
  valid, and `git diff --check` exits 0.
- Safety and volatility checks: the README contains no developer-specific
  absolute path, plaintext credential, private endpoint, public bind, remote
  script pipe, hook bypass, broad-permission command, tracking image/badge, or
  unsupported benchmark percentage/count. Its sole external URL is the HTTPS
  repository clone URL. Platform and product declarations match `Package.swift`.
- Readability/resource checks: the rewrite is 296 lines, 1,642 words, and
  13,261 bytes; it replaces a 1,025-line landing page with a scannable section
  order and links detailed material to authoritative documents. Documentation
  rendering has no runtime resource, load/stress, or application-performance
  path. Accessibility was evaluated through semantic heading order, descriptive
  link text, fenced code labels, a simple labeled table, and the absence of
  image-only content.
- Canonical full gate: `mpd gate test --pass --evidence
  openspec/changes/refresh-github-readme/design.md#tester-evidence` invoked
  `scripts/mpd-test.sh` exactly once and exited 0. MPD parsed and recorded 6,344
  passing tests with zero failures. The serial suite includes the configured
  HypeCoreTests, HypeCLITests, and AppLaunchStateTests, including seeded
  fuzz/property, round-trip/metamorphic, parser, serializer, and protocol
  coverage. The real non-zero count and runner command are persisted in
  `.mpd/state/refresh-github-readme.json`.

No test-only or substantive defect was found. Deployment/publication remains a
separate downstream gate.
