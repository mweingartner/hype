# Design: evidence-backed repository retention audit

## Context

The tracked tree contains exactly 888 paths: 314 production-source, 256 test-source, 162 vendored-dependency, 61 AI-training record/tool, 17 `docs/` documents, 11 root documents, 11 MPD process files, 10 OpenSpec archive files, 10 build/test/deploy tools, 8 other project assets/tools, 7 developer-tool files, 6 OpenSpec schema files, 5 repository configuration files, 2 SwiftPM manifests, 2 durable OpenSpec specs, 2 OpenSpec controls, and one each of self-hosted CI, runtime fixture, license, and GitHub metadata.

The 65 Markdown files classify as: 14 active subsystem references, 8 historical OpenSpec archive documents, 7 explicit historical plans/roadmaps, 7 MPD directives, 7 active durable product docs, 6 dated experiment records, 5 OpenSpec templates, 3 workflow docs, 2 vendor/provenance docs, 2 OpenSpec controls, 2 durable OpenSpec specs, and one each of training guide and conditional harness policy.

Two machine-readable evidence tables are normative inputs:

- `audit-inventory.tsv`: one header plus 888 path rows, with category, extension, size, last meaningful update commit/date, inbound path/basename counts, ownership, and disposition.
- `markdown-audit.tsv`: one header plus 65 path rows, adding document class, nearest five-token-shingle overlap, active evidence, and retention basis.

## Goals / Non-Goals

Goals:

- decide retention for every tracked path;
- give every Markdown file individual, auditable evidence;
- delete only demonstrably obsolete material whose replacement is complete;
- preserve legal, provenance, reproducibility, operational, and open-work records.

Non-goals:

- rewrite historical documents to pretend they were authored under MPD;
- collapse distinct documents merely because topics overlap;
- remove test fixtures, vendor sources, generated runtime artifacts, or command entrypoints solely because textual inbound-reference counts are low;
- alter production behavior, package structure, or deployment.

## Decisions

### 1. The retirement predicate is conjunctive

A file may be deleted only if all are proven:

1. its owner/runtime/build/test/workflow no longer consumes it;
2. no current command, configuration, package manifest, hook, CI workflow, documentation link, or source/test contract depends on it;
3. a named retained replacement preserves every still-valid fact and decision;
4. it contains no unique rationale, unresolved/deferred item, historical evidence, benchmark result, fixture provenance, license notice, or reproducibility data;
5. deleting it does not break a build-discovery convention or paired source/generated distribution contract;
6. relevant relative links and command examples remain valid after deletion;
7. Security and Tester independently confirm the evidence.

Failure to prove any item means retain.

### 2. Category ownership is stronger than text-reference counts, but generated files require producer/consumer proof

SwiftPM owns the 314 production and 256 test files by target-directory discovery, even when no path string appears elsewhere. `Package.swift` owns the 162-file vendored AudioKit tree and its local provenance/license. MPD owns directives, schemas, state, OpenSpec durable specs, and archives. Scripts and CLI entrypoints can be intentionally invoked directly and need not have inbound references. Binary icons, fixtures, package resolution, shell entrypoints, and the Highland archive have explicit packaging, test, or developer-tool roles.

Generated artifacts are individually audited by producer, consumer, and distribution role. The tracked generated-code search found only `Tools/hype-mcp-server/bin/index.js` and `bin/hype-mcp.js`. TypeScript emits `index.js`; the current build copies it byte-for-byte to `hype-mcp.js`. Package bin/start, README, architecture, debug-bridge documentation, and runtime references consume only `hype-mcp.js`. No consumer names `index.js`. Therefore `index.js` is transient while `hype-mcp.js` is the shipped distribution.

### 3. Markdown classifications and decisive watchlist

- `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `architecture.md`, `decisions.md`, HypeTalk references, subsystem guides, and the PR template are active.
- `.mpd/directives/**`, `openspec/schemas/**`, `openspec/specs/**`, and `openspec/AGENTS.md` are active MPD/OpenSpec infrastructure.
- `openspec/changes/archive/**` is intentional immutable change provenance, not disposable duplication.
- Vendor README/license/provenance material is retained for attribution and patch traceability.
- AI-training result documents are dated empirical records paired with tracked datasets and scripts. `RESUME_V4.md` is different: an actionable machine-state handoff claiming a paused iteration-100/PID state, hardcoding another checkout path, and instructing `rm -rf out/adapters`. The ignored local adapters subsequently reached iteration 1200, and current results/default guidance supersede its recommendations. It does contain unique empirical facts, so deletion is ordered only after preserving those facts in a concise, explicitly non-operative subsection of retained `scripts/ai-training/README.md` titled `Historical v3/v4 training snapshot (2026-04-22)`.
- `docs/CodeReviewAndGapsPlan.md` is explicitly marked shipped historical narrative and uniquely records seven commits, historic counts, and deferred items.
- `hype_spritekit_prd_draft2.md` explicitly marks itself pre-implementation design context and preserves cited rationale not duplicated by the current architecture/tutorial.
- `docs/StubsAndCompletionPlan.md`, `docs/HypeFeatureGapImplementationPlan.md`, `docs/MeshyAIIntegrationPlan.md`, and other plans retain unique deferred scope, threat constraints, acceptance criteria, and decision history.
- `ActiveAIDesign.md` and `docs/HyperCardImportPathImplementationPlan.md` remain active design inputs with unimplemented or partially implemented work.
- `CODEX.md` is not replaced by MPD: it governs conditional context retrieval, and local `.dual-graph` / `.dual-graph-context` state exists while being intentionally ignored by git.
- `docs/SelfHostedMacOSRunner.md` is active: `.github/workflows/self-hosted-macos.yml` and `scripts/provision_self_hosted_runner_macos.sh` are tracked. The local pre-push gate being primary does not make the optional self-hosted workflow obsolete.

### 4. Exact deletion candidates

Exactly two baseline paths satisfy the retirement predicate:

1. `Tools/hype-mcp-server/bin/index.js` — SHA-256 `03029ba75d66283dd63a2e0fc87530246ae9d02d95278e8d32c6cfcee8c8f71e`, byte-identical to retained `bin/hype-mcp.js`; transient `tsc` output; zero consumers; replaced by changing copy to move.
2. `scripts/ai-training/RESUME_V4.md` — obsolete machine-specific paused-state instructions; referenced state is superseded and the destructive command is unsafe as evergreen guidance. Before deletion, its unique empirical record must be preserved in the retained training README: v4 initial validation loss 1.311, training loss 0.106 at iteration 100, training loss 0.057 at iteration 190; and v3 validation loss 0.020 at iteration 800 but only 3/26 runtime quality prompts passing. The preserved note must contain no resume commands, filesystem deletion commands, PID/checkpoint availability claims, machine-specific paths, or default-model claims.

The post-change tracked baseline SHALL be 886 files and 64 Markdown files. No other deletion is approved.

### 5. Builder behavior

The Builder first adds the non-operative v3/v4 snapshot to `scripts/ai-training/README.md`, then deletes exactly those two paths. It changes the MCP package build from `tsc && cp ...` to `tsc && mv ./bin/index.js ./bin/hype-mcp.js && chmod ...`, and adds a regression proving a clean build leaves no `bin/index.js`, produces executable `bin/hype-mcp.js`, and keeps compiled output synchronized with `src/index.ts`. It runs TypeScript check/build plus start/help or protocol smoke. Any additional candidate returns to Architecture.

## Alternatives Considered

- Delete all completed plans: rejected because completion does not eliminate unique provenance, deferred work, or decision rationale.
- Delete documents with zero inbound links: rejected generally; accepted for `RESUME_V4.md` only after machine-state and destructive-command evidence proved it obsolete.
- Replace all pre-MPD plans with OpenSpec archives: rejected because those changes predate MPD and no equivalent archives contain their evidence.
- Move historical material to a new archive directory: deferred; movement creates link/history churn without proving that the content is unnecessary.

## Risks / Trade-offs

- Repository remains documentation-heavy → mitigated by explicit status headers and machine-readable classification rather than destructive cleanup.
- Stale statements inside retained docs may mislead → content accuracy is a separate correction task; deleting the whole record is not a safe substitute.
- Generated/vendor trees inflate file count → vendor manifests/licenses remain; generated files are audited individually by producer, consumer, and distribution role.
- False confidence from automated references → every automated signal is advisory and the retirement predicate requires semantic ownership review.

## Verification Plan

- Assert `git ls-files | wc -l == 888` and tracked Markdown count equals 65.
- Assert `audit-inventory.tsv` contains the 888 pre-change paths and marks exactly two deletions; assert the resulting tree has 886 paths.
- Assert `markdown-audit.tsv` contains exactly the 65 tracked Markdown baseline paths.
- Recheck package, MPD/hooks/workflow, AI training config/results, MCP producer/distribution consumer, vendor/license, resources, and fixture ownership.
- Audit retained historical documents for executable, destructive, credential-bearing, or machine-specific commands; historical status must not leave dangerous instructions presented as current operations.
- Verify the retained training README contains the four exact v3/v4 measurements and contains no operational claims copied from the deleted resume guide.
- Run a relative-link audit and distinguish intentional root-relative upstream HyperTalk reference links from repository-relative broken links.
- Run `git diff --check`; because no production change is authorized, build/deploy are readiness checks rather than evidence that a deletion was necessary.

## Architecture conditions (restated canonically after review evidence)

1. Delete exactly `Tools/hype-mcp-server/bin/index.js` and `scripts/ai-training/RESUME_V4.md`; do not expand this set without rerunning Architecture.
2. Never treat age, completion, `draft` naming, zero inbound references, or content similarity alone as proof of obsolescence.
3. Preserve all licenses, attribution, vendor provenance, experiment reproducibility, deferred work, decision rationale, and OpenSpec archives.
4. Preserve SwiftPM-discovered sources/tests/resources; for generated files, preserve consumer-facing distribution output and prove clean reproducibility from source.
5. Do not modify production code, persisted `.hype` documents, fixtures, credentials, Keychain state, user files, or external services for this audit.
6. Do not expose secrets while inspecting configuration; no credential content belongs in evidence artifacts.
7. Evidence remains pre-change complete at 888 paths/65 Markdown; verified post-change tree is exactly 886 paths/64 Markdown.
8. MCP build leaves no `bin/index.js`, produces executable `hype-mcp.js`, and passes TypeScript check plus start/help or protocol smoke.
9. Retained historical docs do not present destructive, credential-bearing, or machine-specific commands as current guidance without an explicit safe historical warning.
10. Before deleting `RESUME_V4.md`, preserve exactly the four unique facts in the retained README: v4 losses 1.311 initial validation, 0.106 training at iteration 100, 0.057 training at iteration 190; v3 validation loss 0.020 at iteration 800 with 3/26 quality prompts passing.
11. The preserved snapshot is explicitly historical and non-operative: no resume/default commands, destructive commands, PID/checkpoint-availability claims, machine paths, or default-model claims.
12. Any contradiction is a blocking Architecture FAIL, not permission for ad hoc deletion.
13. Stage specific files only; never bypass MPD FAIL gates or git hooks.

## Build evidence

**Result: PASS (2026-07-13).** The Builder implemented exactly the two approved
deletions after preserving the four unique experiment measurements. No product
source, persistence format, fixture, credential, user file, or external service
was modified.

- `npm run check && npm run build` in `Tools/hype-mcp-server`: exit 0. The check
  ran `tsc --noEmit`, performed a clean source build, asserted that
  `bin/index.js` was absent, and asserted that retained `bin/hype-mcp.js` was
  executable. A second explicit build also exited 0.
- JSON-RPC protocol smoke: an `initialize` request to the built server returned
  `serverInfo.name == "hype-mcp-server"` and version `0.1.0`; exit 0.
- Artifact comparison: retained `bin/hype-mcp.js` was byte-identical to the
  baseline source-derived compiler output; `bin/index.js` remained absent.
- Inventory verification: 888 unique pre-change tracked paths and 65 unique
  pre-change Markdown paths still exactly match both normative evidence tables;
  the working tree contains exactly 886 retained paths and 64 retained Markdown
  paths. The only absent baseline paths are the two approved deletions.
- Markdown link audit: 37 repository/local targets resolved; 32 root-relative
  `HyperTalkReference` routes were identified separately as intentional upstream
  reference routes; no repository-local target was missing.
- Historical-guidance scan: remaining absolute paths are the playbook's explicit
  editable/exported source declaration and illustrative `/Users/me/Art/...`
  product-language examples. No retained Markdown presents the removed adapter
  deletion command, paused PID/checkpoint state, or obsolete resume procedure as
  current guidance.
- `git diff --check`: exit 0.

The independent Security (code), Test, and Deploy-readiness gates remain open;
this Build result does not approve them.

## Security (code) review

**Result: FAIL (2026-07-13).** Reviewed the actual four-path tracked diff, both
normative inventories, the retained historical snapshot, MCP source/generated
distribution lifecycle, package lock, executable mode, repository cleanliness,
and retained license/provenance paths. The deletion set is exactly the two
Architecture-approved paths; the working tree has exactly 886 retained baseline
paths and 64 retained baseline Markdown paths; both evidence tables remain exact
at 888/65 unique baseline rows; the four unique v3/v4 measurements are retained
in explicitly non-operative prose; `bin/index.js` is absent; `bin/hype-mcp.js`
remains executable and byte-identical to the baseline; and root plus vendored
AudioKit license/provenance material remains present. No additional deletion,
production source, fixture, credential, user-file, external-service, or
dependency-lock change was found.

### Blocking finding

- **[MEDIUM] `Tools/hype-mcp-server/package.json:12` -> make `npm run check`
  non-mutating and compare freshly compiled output with the tracked
  `bin/hype-mcp.js`; keep `npm run build` as the explicit update operation.**
  The new `check` script invokes `npm run build`, which overwrites the tracked,
  consumer-facing executable and then only checks its existence and mode. In an
  isolated copy, appending a harmless comment to `src/index.ts` changed the
  shipped file SHA-256 from
  `03029ba75d66283dd63a2e0fc87530246ae9d02d95278e8d32c6cfcee8c8f71e` to
  `5470dc1cefcfcb0548e3ac410a1f0b31fba4e8fc8ddd6deccd58037908987c32`, while
  `npm run check` still exited 0. Because `scripts/visual_qa.sh` calls this
  nominal verification command, ordinary checking can silently rewrite a
  reviewed distribution artifact and make the worktree dirty rather than detect
  source/generated drift. Compile to a temporary directory (or preserve and
  restore the transient output), compare bytes and executable expectations
  without modifying tracked output, and fail when source and distribution differ.
  After the fix, rerun Security (code); do not advance to Test on this FAIL.

The deterministic MPD secret scan is recorded by the Security(code) gate below;
it is intentionally invoked once for this review. Supply-chain inspection found
a lockfile-v3 package graph of four packages, no lifecycle install hooks in the
MCP package/lockfile, and no dependency or lockfile diff. Those points are sound
but do not mitigate the mutating-check failure.

## Security (code) remediation evidence

The Builder changed only the failed verifier contract. `npm run check` now
creates a temporary directory with `mktemp`, installs an exit/signal cleanup
trap, compiles `src/index.ts` into that isolated directory, byte-compares the
fresh `index.js` with tracked `bin/hype-mcp.js`, and verifies both the absence of
repository `bin/index.js` and the executable mode of the retained distribution.
It never invokes the explicit updating `npm run build` operation.

Closing evidence:

- Clean-tree `npm run check`: exit 0. The tracked distribution SHA remained
  `03029ba75d66283dd63a2e0fc87530246ae9d02d95278e8d32c6cfcee8c8f71e`
  and artifact-scoped git status was identical before and after.
- Isolated-copy source-drift check: a harmless source comment made `npm run
  check` exit 1 as required. The isolated tracked distribution retained the
  same SHA, and no repository-style `bin/index.js` remained.
- Explicit `npm run build`, then `npm run check`: both exited 0. The explicit
  update retained the expected SHA and executable mode, while the subsequent
  verification was non-mutating.
- JSON-RPC protocol smoke: `initialize` returned server name
  `hype-mcp-server`, version `0.1.0`; exit 0.
- Exact 886/64 retained inventory and `git diff --check`: both passed.

This remediation evidence does not approve Security (code); independent
re-review remains required.

## Test evidence

**Result: PASS (2026-07-13).** An independent Tester read the actual diff and
normative inventories, then ran the canonical MPD Test gate exactly once. The
gate executed `scripts/mpd-test.sh`, which serially built the package and ran
the headless-safe `HypeCoreTests`, `HypeCLITests`, and `AppLaunchStateTests`
suites under the Xcode beta toolchain. MPD recorded **6,344 passed, 0 failed**
and advanced to Deploy. The executed core suite includes the reproducibly
seeded `InterpreterFuzzTests` grammar-fuzz, pinned-regression, property, and
metamorphic layers; this was a real non-zero test run rather than a build-only
or no-op runner.

Retention-specific evidence:

- Both evidence tables were parsed as TSV and compared by exact path-set
  equality: 888 unique baseline paths and 65 unique baseline Markdown paths.
  Every inventory row has a category and disposition; exactly the two approved
  paths have deletion dispositions. The effective post-change tree is exactly
  886 paths and 64 Markdown paths.
- The only absent baseline paths are
  `Tools/hype-mcp-server/bin/index.js` and
  `scripts/ai-training/RESUME_V4.md`; no third deletion or unclassified
  baseline file exists.
- A Markdown target audit resolved 37 repository-local references with zero
  missing targets. It separately classified 32 `/HyperTalkReference` routes as
  intentional upstream routes, not repository-relative files.
- The retained historical-command scan found only contextualized current
  administrator guidance (`pmset` for a self-hosted runner and the documented
  MLX memory-limit troubleshooting option), explicitly proposed HypeTalk paths
  under `/Users/me/Art`, the canonical playbook export path, and audit evidence
  quoting the removed unsafe command. No retained product/history document
  presents the deleted adapter-removal/resume procedure, obsolete PID, or
  checkpoint availability as a current operation. The four required numerical
  measurements are present in an explicitly historical, non-operative snapshot.
- Clean-tree `npm run check` exited 0 without changing artifact-scoped git
  status or the shipped executable SHA-256
  `03029ba75d66283dd63a2e0fc87530246ae9d02d95278e8d32c6cfcee8c8f71e`.
  With Node's unrelated compile cache disabled and `TMPDIR` isolated, the
  verifier removed its temporary compiler directory. An isolated source-drift
  mutation made the check exit 1 while leaving the shipped artifact unchanged
  and leaving no `bin/index.js`.
- An isolated `npm ci --ignore-scripts --no-audit --no-fund` succeeded against
  lockfile version 3. Package and lock bytes remained unchanged; the locked
  graph contains four package entries and no dependency diff. Explicit `npm
  run build` reproduced the exact executable SHA, retained executable mode, and
  left no transient `bin/index.js`.
- A real JSON-RPC `initialize` request to the rebuilt executable returned
  `serverInfo.name == "hype-mcp-server"` and version `0.1.0`. This covers the
  functional distribution entrypoint and protocol serialization boundary.
  Error/boundary behavior is covered by isolated drift rejection, absent
  transient-output assertions, exact path/cardinality checks, and zero broken
  local links.
- Non-functional applicability was assessed proportionately: repository
  cleanup adds no UI, so accessibility/design-runtime testing is not
  applicable; it adds no hot path, persistence, networking, concurrency, or
  long-running service behavior, so product performance/load/stress profiling
  would not measure a changed behavior. Resource hygiene was directly tested
  through temporary-directory cleanup, nonmutation, package integrity, and
  reproducible artifact size/content. The full core suite nevertheless retains
  existing concurrency, resilience, and resource regressions.
- `git diff --check` exited 0. No commit, push, deployment, installed app, user
  data, credentials, or external service was touched by the Tester.

## Security (plan) review

**Result: FAIL (2026-07-13).** Reviewed the 888-path inventory, all 65
Markdown classifications, the seven-part retirement predicate, SwiftPM target
and resource discovery, MPD/OpenSpec state and directives, git hooks, the
self-hosted workflow, vendored AudioKit license/provenance, AI-training records,
and the TypeScript MCP source/generated distribution boundary. No credential
contents were copied into this evidence.

### Blocking finding

- **[MEDIUM] `Tools/hype-mcp-server/bin/index.js:1` -> return the exact path to
  Architecture and decide its generated-output lifecycle before Build.** The
  inventory labels this file only as generic `developer automation` and the
  design asserts that every compiled/source pair must be retained. That does
  not prove this particular checked-in file is needed. It is byte-for-byte
  identical to the shipped `Tools/hype-mcp-server/bin/hype-mcp.js` (both SHA-256
  `03029ba75d66283dd63a2e0fc87530246ae9d02d95278e8d32c6cfcee8c8f71e`), while
  `package.json` exposes and starts only `bin/hype-mcp.js`. `tsconfig.json`
  emits `src/index.ts` to `bin/index.js`, and `npm run build` immediately copies
  that output over `bin/hype-mcp.js`. In an isolated repository copy, removing
  `bin/index.js` before `npm run build` still exited 0 and recreated identical
  outputs. Retaining a generated intermediate as tracked source increases
  source/generated drift and review ambiguity; deleting it without also
  defining its ignored/transient lifecycle would instead leave every build
  dirty. Architecture must therefore either (a) name `bin/hype-mcp.js` as the
  retained distribution replacement, remove `bin/index.js` from tracking, and
  ignore or redirect the transient compiler output, or (b) document a concrete
  consumer or release invariant that requires both identical tracked files.

- **[MEDIUM] `scripts/ai-training/RESUME_V4.md:1-18,45,84-85` -> retain only as
  clearly non-operative historical evidence or retire it after mapping unique
  experiment facts into a retained record.** The Markdown table calls this a
  dated experiment record, but the document itself still instructs the reader
  to use it as a resume guide, asserts a 2026-04-22 model as Hype's current
  default, embeds a non-repository absolute path
  (`/Users/michaelweingartner/dev/hype/...`), and includes a destructive
  `rm -rf out/adapters` resume command. That is an exact operational
  contradiction, not merely old prose. Keeping it without a top-level
  historical/non-operative warning can destroy newer adapters or induce an
  obsolete model rollback. Architecture must choose between deletion under the
  retirement predicate and retention with an unmistakable warning that its
  commands/state are historical and must not be executed without revalidation.

### Sound findings and required conditions

- The evidence tables exactly match the baseline: 888 unique tracked paths and
  65 unique tracked Markdown paths, with no missing or extra paths.
- Root and AudioKit license/provenance material is owned and must remain.
- SwiftPM-discovered source, test, and resource files cannot be judged unused
  from textual inbound-reference counts; the plan handles this correctly.
- MPD directives, OpenSpec schemas/specs/archives, hooks, and the self-hosted
  workflow have live lifecycle or configuration ownership and must not be
  removed merely because they are new, historical, optional, or convention
  loaded.
- Dated AI-training results carry reproducibility value, but their commands and
  conclusions must remain explicitly temporal; historical records must not be
  presented as current security or operational guidance.
- Preserve Conditions 1-9. Add a corrected inventory row and a path-specific
  replacement/ownership decision for the MCP compiler intermediate before
  Security (plan) is rerun. Any other generated file must receive the same
  producer/consumer/distribution check rather than blanket pair retention.
- Add a condition that retained historical documents containing executable,
  destructive, credential, deployment, or machine-specific commands are marked
  non-operative at the top and are not linked as current runbooks unless their
  commands are revalidated against the present tree.

## Security (plan) re-review

**Result: FAIL (2026-07-13).** The revised generated-output analysis and MCP
replacement lifecycle are sound: the deletion set is bounded, `hype-mcp.js` is
the named retained distribution, moving rather than copying the compiler output
prevents a dirty tree, and Conditions 1-11 require a clean reproducibility and
protocol proof. The expanded producer/consumer/distribution rule closes the
first review's generated-artifact gap.

One retirement predicate remains unproven:

- **[MEDIUM] `scripts/ai-training/RESUME_V4.md:20-31,112-125` -> map its unique
  empirical facts into a named retained historical result before deletion, or
  revise the retirement decision.** Its machine-state resume instructions and
  destructive command are unquestionably obsolete, and current configuration
  supersedes them operationally. However, the document also uniquely records
  the v4 pause loss trajectory (validation `1.311`, train `0.106` at iteration
  100 and `0.057` at iteration 190), the v3 validation loss `0.020`, and the v3
  comparative result `3/26`. Repository-wide exact searches found those
  measurements nowhere outside this file. `scripts/ai-training/README.md`
  preserves the general declaration/call distribution-mismatch rationale, but
  not these empirical results. Git commit
  `849ff7f5b9c3ea751478df0ee39f3635df316ac8` makes the deleted file recoverable,
  but the plan's conjunctive predicate 3 requires a named retained replacement
  and predicate 4 prohibits deleting unique historical evidence. Merely naming
  generic “README/results and git history” does not satisfy both predicates as
  currently written. Copy only the unique measurements and temporal context
  into an appropriate retained result record (without the unsafe runbook), or
  explicitly return to Architecture to justify and specify version-control
  history as the durable replacement contract.

No additional deletion candidate or credential exposure was found. The exact
888/65 pre-change and 886/64 post-change cardinality conditions, legal/vendor
preservation, MPD/OpenSpec/hook/CI ownership, historical-command safety rule,
and prohibition on deletion-set expansion remain sound.

## Deploy readiness evidence

**Result: PASS / no installable change (2026-07-13).** All mandatory upstream
gates passed. This audit changes repository documentation and the developer-only
TypeScript MCP build workflow; it does not change Hype application source,
resources, dependencies, or bundle contents. Replacing `/Applications/Hype.app`
would therefore manufacture runtime proof for an unchanged binary. The verified
release state is the canonical full suite plus the reproducible MCP JSON-RPC
initialize smoke recorded above.

## Conditions for Builder

1. Delete exactly `Tools/hype-mcp-server/bin/index.js` and `scripts/ai-training/RESUME_V4.md`; do not expand this set without rerunning Architecture.
2. Never treat age, completion, `draft` naming, zero inbound references, or content similarity alone as proof of obsolescence.
3. Preserve all licenses, attribution, vendor provenance, experiment reproducibility, deferred work, decision rationale, and OpenSpec archives.
4. Preserve SwiftPM-discovered sources/tests/resources; for generated files, preserve consumer-facing distribution output and prove clean reproducibility from source.
5. Do not modify production code, persisted `.hype` documents, fixtures, credentials, Keychain state, user files, or external services for this audit.
6. Do not expose secrets while inspecting configuration; no credential content belongs in evidence artifacts.
7. Evidence remains pre-change complete at 888 paths/65 Markdown; verified post-change tree is exactly 886 paths/64 Markdown.
8. MCP build leaves no `bin/index.js`, produces executable `hype-mcp.js`, and passes TypeScript check plus start/help or protocol smoke.
9. Retained historical docs do not present destructive, credential-bearing, or machine-specific commands as current guidance without an explicit safe historical warning.
10. Before deleting `RESUME_V4.md`, preserve exactly the four unique facts in the retained README: v4 losses 1.311 initial validation, 0.106 training at iteration 100, 0.057 training at iteration 190; v3 validation loss 0.020 at iteration 800 with 3/26 quality prompts passing.
11. The preserved snapshot is explicitly historical and non-operative: no resume/default commands, destructive commands, PID/checkpoint-availability claims, machine paths, or default-model claims.
12. Any contradiction is a blocking Architecture FAIL, not permission for ad hoc deletion.
13. Stage specific files only; never bypass MPD FAIL gates or git hooks.
