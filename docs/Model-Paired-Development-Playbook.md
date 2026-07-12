---
type: guide
title: The Model-Paired Development Playbook
description: Reusable recipe for building quality software with design, architecture, security, build, test, and deployment gates.
updated: 2026-07-09
---

# The Model-Paired Development Playbook

*How to build quality software by pairing with AI models — a reproducible recipe.*

**Protocol version:** 2026-07-09. This Markdown file is the canonical editable
source; `/Users/mweingar/Documents/ModelPairedDev.pdf` is a generated export.

This guide distills the method used to build **Hype** (a Swift 6 HyperCard
revival) with an AI coding agent. It is not a description of one project; it is a
**transferable operating system** for human + model collaboration that produces
shippable, verified, maintainable software instead of plausible-looking drafts.

The core idea in one sentence: **treat the model not as an oracle you trust, but
as a team you orchestrate — with written contracts, separated adversarial roles,
and gates that make verification non-optional.**

---

## Table of contents

1. [Why this works (the value)](#1-why-this-works-the-value)
2. [The three pillars](#2-the-three-pillars)
3. [Pillar I — Markdown as the shared brain](#3-pillar-i--markdown-as-the-shared-brain)
4. [Pillar II — Separated adversarial personas](#4-pillar-ii--separated-adversarial-personas)
5. [Pillar III — Testing & verification as a gate](#5-pillar-iii--testing--verification-as-a-gate)
6. [The pipeline (the workflow)](#6-the-pipeline-the-workflow)
7. [Setup: stand it up from scratch](#7-setup-stand-it-up-from-scratch)
8. [A worked example](#8-a-worked-example)
9. [Compliance: what to look for in the output](#9-compliance-what-to-look-for-in-the-output)
10. [Anti-patterns & hard-won lessons](#10-anti-patterns--hard-won-lessons)
11. [Appendices — copy-paste templates](#11-appendices--copy-paste-templates)

---

## 1. Why this works (the value)

A single model in a single context, asked to "build feature X," fails in
predictable ways:

| Failure mode | What it looks like | What the method does about it |
|---|---|---|
| **Anchoring** | The model commits to its first idea and rationalizes around it. | A separate *architect* commits the design to writing *before* any code exists, so the plan can be critiqued on its own. |
| **Plausible-but-wrong** | Code that compiles and reads well but is subtly incorrect or insecure. | A separate *security* persona and a separate *tester* persona are each incentivized to **break** the work, not bless it. |
| **Self-confirmation** | "Tests pass." (They were never run, or the runner silently no-op'd.) | Verification is **empirical and shown** — real command output, real counts, before/after numbers. You *verify your verification*. |
| **Context rot** | Long sessions lose the plan; decisions drift. | The plan and the intent live in **durable markdown files**, not in volatile chat history. |
| **Scope creep / silent damage** | The model reformats a file, sweeps unrelated changes into a commit, or "improves" something you didn't ask about. | **Pre-grep the tree**, stage *specific* files, one logical change per commit, and surface anything surprising instead of acting on it. |

The value proposition, stated plainly:

- **Higher correctness per unit of human attention.** The adversarial roles catch
  classes of defects a single pass misses, *before* they reach you.
- **Reviewable trail.** Every step leaves an artifact — a plan, a security
  verdict, a test count, a commit — so you can audit *how* a conclusion was
  reached, not just accept it.
- **Durable intent.** The domain knowledge accumulates in markdown the model
  re-reads each session, so quality compounds instead of resetting.
- **Proportionate.** Every gate remains visible, while artifact depth scales to
  semantic risk; small work stays concise without creating bypasses.

This is the difference between *"the model wrote some code"* and *"a disciplined
team shipped a verified change."*

---

## 2. The three pillars

Everything else is mechanics. The method rests on three pillars:

1. **Markdown as the shared brain** — written intent, written plans, written
   decisions. The model reads them before acting and writes them after.
2. **Separated adversarial personas** — designer, architect, security, builder,
   tester, run
   as distinct sub-agents with distinct incentives and (deliberately) different
   model tiers.
3. **Testing & verification as a gate** — not a final chore but an invariant that
   *blocks* progress, backed by real evidence.

A change is "done" only when all three have been satisfied: it matches written
intent, it survived adversarial review, and its correctness was demonstrated.

---

## 3. Pillar I — Markdown as the shared brain

Models have no memory between sessions and a fragile memory within one. Markdown
files are how you give them a **persistent, shared, and authoritative** picture
of the project. Treat docs as infrastructure, not afterthought.

### 3.1 The layered document system

Use four layers, from most general to most specific:

| Layer | File(s) | Role | Lifespan |
|---|---|---|---|
| **Operating rules** | `~/.claude/CLAUDE.md` (global), project `CLAUDE.md` | *How we work* — pipeline, source-control rules, model assignments, conventions. | Permanent, rarely changes |
| **Collaboration principles** | e.g. `ddd-collaboration.md` | *How we think* — domain modeling, ubiquitous language, when ceremony applies and when it doesn't. | Permanent |
| **Intent & design** | `architecture.md`, `decisions.md`, a PRD, domain references | *What we're building and why* — the living source of truth for the system. | Lives with the project |
| **Plan artifacts** | `/tmp/architect_*.md`, audit docs, baseline docs | *What we're doing right now* — the per-task plan and its measurements. | Per task; the durable ones get promoted into the design layer |

**Hype examples:** `architecture.md` (the 200KB+ living design), `decisions.md`
(why choices were made), `docs/HyperTalkCompatibilityAudit.md` (the analysis +
the honest list of remaining gaps), `docs/HypeTalkBenchmarkBaseline.md` (the
measured speed/size baselines and every optimization wave). The global
`CLAUDE.md` carries the pipeline and source-control law; `ddd-collaboration.md`
carries the modeling principles.

### 3.2 How the model uses these (the discipline)

- **Read before acting.** The very first step of any non-trivial task is to read
  the intent-shaping docs. ("Read all the .md files that shape the intent" is a
  literal instruction worth giving.) This aligns the model with the domain's
  *ubiquitous language* — use the project's exact terms (`stack`, `card`,
  `chunk`, `the target`) in code, comments, and commits, never a paraphrase.
- **The plan is a written contract.** The architect's plan is saved as a file and
  becomes the builder's exact specification. A written contract dramatically
  reduces drift between "what we agreed" and "what got built."
- **Write after acting.** When a task lands, update the design-layer docs in the
  *same* change: the audit doc gains the new capability, the baseline doc gains
  the new measurements, `architecture.md` gains the new subsystem. Stale docs are
  worse than no docs — they actively mislead the next session.
- **Promote durable plans.** A `/tmp` plan that proved correct gets its lasting
  conclusions folded into `architecture.md` / `decisions.md` so the knowledge
  survives.

> **Rule of thumb:** if a decision was non-obvious, it belongs in a doc. If a doc
> names a file/flag/function, that reference must still be true — verify before
> relying on it.

### 3.3 Project memory

Beyond the repo docs, keep a small **cross-session memory** of environment facts
that aren't derivable from the code: a broken toolchain workaround, a flaky test
runner, a deploy quirk. (In Hype: "the machine's command-line tools are broken;
build via `DEVELOPER_DIR=…Xcode-beta`; the test runner has no `timeout` binary.")
These are the facts that, when forgotten, cost an hour every session.

### 3.4 This pattern is becoming a standard (OKF)

The "markdown as the shared brain" pattern is converging into an open standard.
Google Cloud's **Open Knowledge Format (OKF, v0.1, June 2026)** formalizes almost
exactly this: plain markdown files in git, each with a small YAML frontmatter
block (a required `type` plus optional `title`/`description`/`tags`/`timestamp`),
cross-linked into a graph, readable by humans, LLMs, and tooling alike — chosen
precisely because "the value of a knowledge format comes from how many parties
speak it." If you built the layered document system above, you've already built
most of OKF.

Two practical takeaways: (1) **adopt the cheap conventions** — a consistent
frontmatter (`type`/`title`/`description`/`updated`) on durable docs makes them
queryable and gives a staleness signal, and **standard relative markdown links**
keep the graph resolvable in any tool. (2) **Don't over-conform.** OKF's primary
ontology is *data assets* (datasets, tables, metrics, lineage) and its payoff is
cross-org/cross-tool interop; a single-team dev project rarely needs the
directory restructure or the interop machinery, and OKF's atomized concept-per-
file model fights the long-form *narrative* docs (this playbook, decision
rationales) that an LLM benefits from reading whole. Borrow the format
conventions; keep your narrative. OKF is, however, a strong choice as an *export*
format if you ever publish your project's own domain knowledge for outside agents
to consume.

---

## 4. Pillar II — Separated adversarial personas

The heart of the method. Instead of one model doing everything, you run distinct
sub-agents, each with a single job, its own system prompt, and a deliberately
chosen model tier. **Separation creates the adversarial diversity that catches
what one pass cannot.**

### 4.1 The five personas

| Persona | Model tier | Tools | Single job | Why it's separate |
|---|---|---|---|---|
| **Designer** | **Opus** (strongest) | Read-only + design/runtime inspection | Audit the existing product design, create the design contract, review the architecture for fidelity, and sign off the built surface. **Writes no production code.** | A feature can be technically complete yet undiscoverable, incoherent, or inelegant. A dedicated design critic protects user intent at three separate gates. |
| **Architect** | **Opus** (strongest) | Read-only + web + Task | Explore exhaustively, design, produce a zero-ambiguity written plan. **Writes no code.** | Planning is the highest-leverage step; it deserves the strongest model and a context uncontaminated by implementation detail. |
| **Security** | Sonnet | Read-only + web | Find real vulnerabilities in the *plan*, then in the *code*. Cite file:line + severity + exact fix. | A reviewer who also wrote the code rubber-stamps it. A dedicated skeptic is incentivized to find holes. |
| **Builder** | Sonnet | Read/Edit/Write/Bash | Implement the plan faithfully, match existing patterns, keep the build green. | Implementation should *follow* the contract, not re-litigate the design mid-stream. |
| **Tester** | Sonnet | Read/Edit/Write/Bash | Read the real implementation; run functional, non-functional, regression, and applicable fuzz/property/metamorphic testing; run the **full** suite; fix until green. | A tester who only saw the plan tests the fantasy; one who reads the code tests reality. |

> **Model-tier nuance (important):** the persona definition files may default to
> one tier, but the operating rules **override the model per invocation** and you
> should pass it explicitly every time. The judgment/creative planning and
> validation phases — **Design, Architecture, and Doc Validation** — are the
> deep-cognition tier; the execution/synthesis/review phases are standard.
> **Claude:** Designer and Architect → `fable` (fall back to the latest Opus when
> Fable is unavailable), including as Doc Validation reviewers; Security, Builder,
> Tester, Documenter → the latest `sonnet`. **Codex:** the deep tier → GPT-5.6
> Sol; the standard tier → Terra (Luna, the lightest tier, is unassigned by
> default). Spend the deepest model where judgment matters most — design,
> architecture, and validating the docs — and the standard model for the
> well-specified execution, synthesis, and review roles.
> Don't rely on the agent-definition default — state the tier on every call.

### 4.2 Why distinct personas beat one smart context

- **Incentive separation.** The builder wants the code to work; the security and
  tester personas want it to *fail*. Running them as separate agents makes the
  skepticism real instead of performative.
- **Context hygiene.** The architect reasons about design without 2,000 lines of
  half-written code crowding its attention. The tester reads the *final* code
  fresh, not the optimistic narration of the builder.
- **A written hand-off forces precision.** Because the plan must travel from
  architect to builder as text, it cannot be vague. "Somewhere in the parser" is
  not a plan; "`Parser.swift:530`, add a case mirroring `parsePutStatement`" is.
- **Defects are caught at the cheapest stage.** A flaw found in the *plan* costs a
  paragraph to fix; the same flaw found after implementation costs a rewrite. The
  plan-stage security pass exists precisely to move discovery left.

### 4.3 Designer discipline

The Designer owns the user's experience, not decoration. Before proposing a
change, it audits the existing screens, components, tokens, interaction patterns,
copy, accessibility behavior, and relevant prior design decisions. It then makes
every capability and state discoverable, legible, coherent, and appropriately
prominent. "Elegant" must be made auditable through acceptance criteria tied to
the existing design system, information hierarchy, platform conventions,
accessibility, adaptive behavior, and empty/loading/error/partial/overflow states.

The Designer runs at three distinct points:

1. **Design Mock** — produce the design specification and acceptance criteria
   before Architecture.
2. **Design Review/Revision** — review the Architect's plan before Build and send
   it back if the plan degrades, buries, or omits the design intent.
3. **Design Sign-off** — inspect the actual built surface and representative
   runtime states before Test. This is a visual/interaction conformance gate, not
   a substitute for independent functional testing.

The three Design phases may be recorded as **N/A only when the change has no
human-visible behavior or interaction impact**, with a written rationale. CLI
behavior, user-facing errors, configuration ergonomics, accessibility, and
developer-facing workflows can carry UX and must not be dismissed as "backend"
without analysis.

### 4.4 The hand-off contract

Each persona's output is the next one's input, verbatim. The critical
augmentation the Hype workflow adds: the Designer's acceptance criteria and the
architect's plan are separate written contracts. The plan ends with a **"Conditions
for Builder"** section enumerating every security/correctness invariant discovered
during planning. The plan must also map each identified risk or invariant to
expected verification and state why any test category is inapplicable. These
contracts travel together so the builder cannot miss design, security, or test
intent.

---

## 5. Pillar III — Testing & verification as a gate

Verification is not the last chore; it is an **invariant that blocks progress**.
The discipline has three parts: *who writes the tests*, *how good the tests are*,
and *who enforces the gate* — and the answer to the last one should be **the
machine, not the model**. A model can be fooled or fool itself (see §5.3); a
required CI check cannot be sweet-talked. This is the line between a solid
*practice* (we review carefully and run tests) and a solid *system* (unverified or
insecure code physically cannot land).

### 5.1 Tests are written with the code, not bolted on

- For **new (greenfield) code**, the builder writes the tests **inline, in the
  same pass** as the implementation. Code and its tests are one unit of work.
- The **tester persona** reads the real implementation, deepens the Builder's
  coverage, investigates failures, and adds regression tests when a bug is
  found. It independently exercises functional behavior, error and boundary
  paths, integration, and the non-functional qualities affected by the change:
  performance, load/stress, resource use, concurrency, accessibility, resilience,
  and other applicable quality attributes.
- The test artifact includes a risk-to-test matrix. Each plan invariant maps to
  functional, regression, non-functional, fuzz, property, or metamorphic
  evidence; omitted categories carry an explicit applicability rationale.
- Tests must assert **content**, not existence. "Returns non-nil" is not a test.
  "Returns `8` for `value(\"2 * (3+1)\")`" is.

### 5.2 The gates (non-negotiable invariants)

1. **All tests pass before deployment.** Not "the new tests" — the **full
   suite**, to catch regressions.
2. **The gate is machine-enforced, not self-reported.** At minimum a **pre-push
   git hook** runs the build + full suite locally and aborts the push if it
   fails; with shared infrastructure, CI runs it on every push/PR and `main`
   requires the check (branch protection). "Tests pass" reported by the agent is
   a *claim*; a hook that blocked the push, or a green required check, is a
   *fact*. (See §5.7 for the enforcement ladder and toolchain specifics.)
3. **Code cannot reach Design Sign-off or the Tester without passing the
   code-stage Security gate.**
4. **Stage specific files; never `git add -A`.** You commit what you reviewed.
5. **One logical change per commit**, with a clear message and co-author tag.
6. **One install/deploy at the end**, not after every phase. The Deploy stage is
   mandatory as a readiness and real-target verification gate, but it does not
   create authority for an external release. Actually deploy only when the user
   explicitly requested it or current repository instructions name the command,
   target, and workflow as already authorized. Otherwise stop with deploy-ready
   evidence. Consequential deployments require target confirmation, a rollback
   plan, and post-deploy verification.

### 5.3 Verify your verification

The most dangerous bug is a **broken verifier that reports success.** A real
example from the Hype build: the environment had **no `timeout` binary**, so every
`timeout 60 swift test` silently failed with "command not found" and **never ran
the tests** — producing false "all green" conclusions for an entire session.

The lesson is a permanent rule: **when a result is suspiciously clean, doubt the
instrument before you trust the outcome.** Concretely:

- Confirm the test command actually *executed* tests (a real, non-zero count).
- Prefer deterministic runs (e.g. serial mode) when a parallel runner stalls.
- Resolve the *freshest* build artifact — stale binaries lie. (Hype had two build
  output directories; tests were silently exec'ing a week-old binary.)
- For performance claims, **measure before *and* after**, take the **median of
  several runs** (single runs are noisy), and compare on the **same build
  system**. Don't report a "win" from one noisy sample.
- For "it works" claims, **run the real thing** — drive the live app, hit the
  real interface, compile for the real target — not a proxy.

### 5.4 Empirical claims, not adjectives

Replace "much faster" with a number and the command that produced it. In Hype, the
speed optimization wasn't "loops are faster" — it was *"a 2000-iteration loop
dropped from ~67 s of frame-sleep wall-clock to ~2 ms; compute-heavy workloads
publish 2–4× less,"* each backed by a benchmark run. The size win wasn't "smaller"
— it was *"Interpreter `__text` 1.56 MB → 824 KB (−48%), measured with `size -m`
on the same toolchain."*

### 5.5 Property, fuzz & metamorphic testing (for parsers and formats)

Example-based tests cover the cases you thought of. For any code that consumes
**structured input** — a parser, interpreter, serializer, codec, or wire
protocol — the cases you *didn't* think of are where the bugs live, and you need a
generator to find them.

- **Grammar fuzzer.** A **seeded, reproducible** PRNG generates bounded, valid-ish
  inputs; you assert oracle-free **properties** on each: it never crashes/traps
  (a trap killing the test process *is* the finding), it terminates, and it is
  **deterministic** (same input → same output). Seed-per-case means every failure
  replays exactly; pin failing seeds as permanent regressions.
- **Metamorphic relations.** When there's no reference implementation to diff
  against, assert equalities that must hold for *any* operands: `x + 0 == x`,
  `a + b == b + a`, write-then-read round-trips, `a < b == b > a`. You don't
  assert *what* the answer is — only that two paths that must agree, do.
- **Differential testing** where a reference exists (a second implementation, a
  spec, a previous version): run both, diff the outputs.

In Hype this is `Tests/HypeCoreTests/InterpreterFuzzTests.swift` — a grammar
fuzzer over generated HypeTalk handlers plus seven metamorphic relations. It is
the single highest-ROI reliability addition for an interpreter, and it runs as
part of the normal suite so the CI gate covers it.

### 5.6 Measure test adequacy, not green-count

"3,000 tests pass" says nothing about whether they would *catch* a regression.
Two cheap, high-signal measures answer that:

- **Coverage** finds branches no test exercises.
- **Mutation testing** injects bugs and checks the suite *fails* — the only direct
  measure of whether your tests are any good. A suite that stays green under
  mutation is theater.

Report these, not just the pass count.

### 5.7 The enforcement ladder (local hook → CI), and deterministic security

The personas *review*; something mechanical must *enforce*. "Enforced" is a
ladder — climb as far as your project's infrastructure and risk justify, but get
on it:

1. **Self-reported (weakest).** The agent says "tests pass." Necessary but
   fakeable — this is the rung to climb *off* of.
2. **Local pre-push hook (no infrastructure).** A tracked `pre-push` hook runs
   the build + full suite (incl. the fuzz suite) and **aborts the push** if it
   fails. The machine enforces it, on your machine, with zero external setup. A
   red suite physically blocks the push; bypass requires a deliberate
   `--no-verify`. This is the pragmatic default and is often *enough* for a solo
   or small project.
3. **CI required checks (strongest).** Workflows run the suite + scans on every
   push/PR and `main` *requires* them (branch protection), so nothing lands
   unverified even across machines and contributors. Add this when you have
   shared infrastructure and more than one contributor.

**Toolchain reality check.** CI needs a runner with your toolchain. If the
project pins a beta or unusual SDK (Hype pins a beta Swift/macOS SDK that
GitHub-hosted runners don't carry), hosted CI can't build it — your options are a
self-hosted runner (more setup) or, more simply, the **local pre-push hook**.
Hype took the hook: it enforces build + test + fuzz on every push to `main`
without any CI infrastructure. Don't let "we can't run hosted CI" become an
excuse for *no* gate — a pre-push hook is always available.

**Deterministic security tooling** belongs on whichever rung you're on — the LLM
security persona is *necessary but not sufficient* and should confirm these
exist, not replace them:

- **Secret scanning** (e.g. gitleaks) — unambiguous; hard-fail on any finding.
- **SAST** (e.g. Semgrep source-pattern; CodeQL when a build is available) — the
  backstop that catches taint flows and dangerous patterns an LLM misses.
- **Dependency / SCA alerts** (e.g. Dependabot) — known-CVE and update tracking.

Source-based scanners (gitleaks, Semgrep) need no toolchain, so they can run in
the pre-push hook *or* hosted CI even when the build can't. Add them to the rung
you have.

---

## 6. The pipeline (the workflow)

Tie the pillars together into one ordered sequence. Rigor scales with semantic
risk, but lifecycle order does not:

```
Design Mock → Architecture → Design Review/Revision → Security (plan) →
Build → Security (code) → Design Sign-off → Test → Documentation → Deploy → Doc Validation
```

Pre-grep (`git status` plus existing implementation/design/test inspection) is
required setup before the persona phases. Commit is source-control work performed
after Test and before an authorized Deploy when the repository workflow requires
it; it is not a persona gate.

### 6.1 Applicability and rigor

Every change passes Architecture, both Security gates, Build/change execution,
Test, and Deploy/readiness. Small or documentation-only changes use proportionate
artifacts, but no size-based category silently bypasses security impact analysis
or verification. A one-line entitlement, dependency, parser, signing, network,
CI, or deployment change can be high risk.

Only **Design Mock, Design Review/Revision, and Design Sign-off** may be marked
N/A, only when the change has no human-visible behavior or interaction impact,
and only with a written rationale recorded before Build.

Novel threat surface — auth/credentials, network egress, untrusted input or file
I/O, dynamic execution, sandboxing, cryptography, persistence formats, or any
capability with no shipped analog — requires the deepest Security and Tester
evidence, independently separated roles, an explicit threat model, and rerunning
Security after every fix. Routine changes keep the same phases with proportionate
depth.

### 6.2 Gate semantics and backward edges

Every review ends in **PASS**, **CONDITIONAL PASS**, or **FAIL**. A conditional
pass lists each condition, its owner, and the evidence needed to close it;
unresolved Security or Test conditions block actual deployment. A FAIL blocks
progress. Findings return work to the earliest affected Design, Architecture, or
Build phase, and every invalidated downstream gate reruns after material changes.

- **After Design Mock:** present the design specification to the human when
  engaged; Architecture builds against it.
- **After Architecture:** present the plan summary. Design Review/Revision must
  approve UI/UX fidelity, then Security must approve the plan.
- **After Build:** Security reviews the actual code on disk. Design Sign-off then
  inspects the real built surface and representative states; it cannot approve
  unseen work.
- **Test:** the Tester reads the implementation and executes the risk-to-test
  matrix, the full project gate, and real-target checks. Commands, counts, exit
  status, and any omitted-category rationale are reported.
- **Deploy:** deploy only with explicit authority or concrete current repository
  instructions naming the command and target; otherwise produce deploy-ready
  evidence. Verify the real target after deployment.

### 6.3 Keep the human in the loop at decision points

The pipeline is autonomous *execution*, not autonomous *judgment*. When a genuine
trade-off exceeds a pre-agreed threshold, **stop and ask** rather than rationalize
past it. In Hype, an `-Osize` build flag delivered a 48% size cut but a >10% CPU
cost on one path — exceeding the architect's pre-set gate — so the decision went
back to the human with the numbers and the recommendation, instead of being
quietly absorbed. (The reverse is also true: don't ask about choices with an
obvious default — pick it, state it, move on.)

---

## 7. Setup: stand it up from scratch

Everything you need is a handful of files and a model runner that supports
sub-agents (the examples use Claude Code's `Task`/sub-agent mechanism).

### 7.1 Directory layout

```
~/.claude/
  CLAUDE.md                 # global operating rules (pipeline, source control, model tiers)
  ddd-collaboration.md      # collaboration / domain-modeling principles
  agents/
    designer.md             # persona: design mock, plan review, built-surface sign-off
    architect.md            # persona: model + tools + system prompt
    security.md
    builder.md
    tester.md
  commands/
    pipeline.md             # the invocation guide you can re-read on demand
<your repo>/
  CLAUDE.md / AGENTS.md     # project-specific rules + per-task verification workflow
  architecture.md           # living design (source of truth)
  decisions.md              # why choices were made
  docs/                     # audits, baselines, design notes, this playbook
  .githooks/
    pre-push                # build + full test suite (incl. fuzz) — the local gate
  scripts/
    install-git-hooks.sh    # sets core.hooksPath = .githooks (one-time)
  .github/                  # OPTIONAL stronger tier, only if you have CI infra:
    workflows/ci.yml        #   build/test (needs a runner with your toolchain)
    workflows/secret-scan.yml, sast.yml   # gitleaks + Semgrep (SDK-independent)
    dependabot.yml          #   dependency updates + CVE alerts
```

### 7.2 The files to write (in order)

1. **Persona definitions** (`agents/*.md`). Each is a markdown file with
   frontmatter (`name`, `description`, `model`, `tools`) and a system prompt that
   gives the persona one job and explicit rules. Use the appendix templates as a
   starting point. Pin the **tools** narrowly: Designer, Architect, and Security
   are non-implementation roles; Builder and Tester get Edit/Write/Bash. Designer
   may use read-only runtime/design inspection tools needed to examine the real
   surface but never writes production code.
2. **The global `CLAUDE.md`** — the operating rules: the pipeline, the tier
   trigger list, the **mandatory model assignments**, and the source-control law
   (stage specific files, one logical change per commit, co-author tag, never
   commit secrets/build artifacts, `.gitignore` essentials).
3. **A collaboration-principles doc** if your domain is rich enough to warrant it
   (skip for thin/technical projects — the ceremony is a tax that only pays off in
   complex domains).
4. **Per project:** a `CLAUDE.md`/`AGENTS.md` of project conventions and a
   per-task verification workflow, plus an `architecture.md` you grow as you
   build. Seed `decisions.md` the first time a non-obvious choice is made. Put the
   gate commands *here*, where they're read on every task (how to run the suite,
   the fuzz filter, the deploy step) — the global rules carry the principle, the
   project file carries the exact commands.
5. **The machine-enforced gate (start local).** Add a tracked `.githooks/pre-push`
   that runs the build + full suite and aborts the push on failure, plus a
   one-line installer (`git config core.hooksPath .githooks`). This gives you
   enforcement with zero infrastructure and works regardless of toolchain — the
   right default for solo/small projects. **Then, if and when you have CI infra**,
   add `.github/` workflows as the stronger tier: source-based scans (gitleaks,
   Semgrep) and dependency alerts run on hosted runners immediately; the
   build/test gate needs a runner with your toolchain (self-hosted if you pin a
   beta/unusual SDK), after which branch protection makes `main` require the
   checks. Climb the ladder (§5.7) as far as your project warrants — but never
   stay on rung 1 (self-reported).

### 7.3 Configuration that matters

- **Model tiers, explicit per call.** Designer and Architect = strongest;
  security/builder/tester = a fast capable model. State the tier on every invocation — don't trust
  defaults.
- **Read-only tools for the thinkers.** Enforced tool scoping is what makes "the
  architect writes no code" a guarantee instead of a hope.
- **A real test runner and a real deploy command**, documented in the project
  `CLAUDE.md`, so every persona knows how to build, test, and ship.
- **Live interfaces where possible.** If your app exposes an automation/MCP
  interface, wire it in so verification can drive the *real* product, not a stub.

### 7.4 Cost & ergonomics

A deep run spends real tokens and exhaustive reads. That's the point — you're
buying defect discovery you'd otherwise pay for in production. Keep it
proportionate by scaling artifact depth to semantic risk and doing **one install
at the end** rather than rebuilding after every phase; do not delete mandatory
gates to save time.

---

## 8. A worked example

A real task from the Hype build, start to finish, showing the method in motion.

**Request:** *"Analyze HypeTalk's language support, ensure it covers classic
HyperTalk, and optimize the interpreter for speed and size — small footprint on
mobile, ideally watchOS-capable."*

1. **Read the intent.** First action: read the language reference, the
   compatibility audit, `architecture.md`'s interpreter section, and the benchmark
   baseline doc — to speak the domain's language and learn what already exists.
2. **Establish baselines (verify-first).** Before optimizing, *measure*: capture
   the interpreter's `__text` size and a benchmark of representative workloads, so
   every later claim has a before-number.
3. **Design applicability.** This interpreter task had no new human-visible
   interaction, so the three Design phases were recorded N/A with that rationale.
4. **Architect the plan (Opus, read-only).** Produce a phased plan — compatibility
   gaps, speed, size, watchOS — each phase with file paths, exact edits, expected
   wins, and a **"Conditions for Builder"** section (e.g. "dynamic `value()`
   evaluation must reuse the existing recursion-depth and byte-size caps").
5. **Security-review the plan, then implement in slices.** Close the compatibility
   gaps (with inline fidelity tests); then the speed change (gate per-statement
   work to visible effects) — *proven* with publish-count and wall-clock numbers,
   and a correctness argument that the final render still flushes; then the size
   change (`-Osize`) — *measured* at −48% with a median-of-three CPU cost.
6. **Security-review the code and verify independently.** Review the actual diff,
   then have the Tester exercise functional behavior, regressions, performance,
   and the seeded fuzz/property suite. "watchOS-capable" wasn't asserted — a
   throwaway sub-agent and then a committed script **compiled the interpreter
   kernel for the watchOS triple**, proving 192/214 source files build for watch
   and naming the exact device-only files that don't.
7. **Surface the trade-off.** The `-Osize` CPU cost exceeded the pre-agreed gate,
   so the decision went **back to the human** with the numbers — not quietly
   absorbed.
8. **Land and deploy/readiness-check it cleanly.** Full suite green (3,026 tests,
   serial for determinism);
   **specific files staged** (the unrelated work-in-progress from another task was
   *excluded*, not swept in); logical commits with co-author tags; docs updated in
   the same change; push.

Notice what the method bought: a size win and a portability claim that are
**true and demonstrated**, a speed win backed by numbers, zero collateral damage
to unrelated work, and a paper trail you can audit.

---

## 9. Compliance: what to look for in the output

This is how you, the human, tell whether the model is **actually following the
method** versus producing a convincing imitation of it. Use these as a live
checklist while reviewing the model's work.

### 9.1 Green flags (the method is being followed)

- **The Designer is grounded in existing work.** The mock cites established
  components/patterns/tokens, covers every state and accessibility requirement,
  and ends in checkable acceptance criteria. Review and Sign-off compare the plan
  and real built surface against that contract.
- **The architect's plan is specific.** File paths, type signatures, dependency
  order, edge cases, and a **"Conditions for Builder"** section. Not prose like
  "we'll update the parser to handle this."
- **Security cites coordinates.** Each finding has `[SEVERITY] FILE:LINE →
  exact remediation`, and an explicit **PASS / CONDITIONAL PASS / FAIL** verdict.
  It names what it *did* review, and admits what it *couldn't*.
- **Tests are real and counted.** The output shows a concrete suite result
  (*"3,026 tests passed"*), run on the **full** suite, with assertions on content,
  a risk-to-test matrix, applicable functional/non-functional/fuzz evidence, and
  explicit rationale for omitted categories.
- **Claims carry evidence.** Performance/size statements come with the command and
  before/after numbers; "it works" comes with output from running the real thing.
- **Commits are clean.** *Specific* files staged, one logical change each, clear
  message, co-author tag. `git status` after shows nothing unexpected swept in.
- **Surprises are surfaced, not actioned.** When the model finds something it
  didn't expect (unrelated changes in the tree, a doc that contradicts the code),
  it *reports* it rather than silently "fixing" it.
- **Trade-offs come to you.** Genuine judgment calls that exceed a threshold are
  raised with options and a recommendation.
- **The gate is the machine.** Something mechanical ran the suite and would have
  blocked on failure — a pre-push hook that aborts the push, or a required CI
  check — not just the agent saying "tests pass"; parser/format changes show the
  fuzz suite green; the security pass *confirms* the deterministic scans exist.

### 9.2 Red flags (compliance theater or corner-cutting)

- **Adjectives instead of numbers.** "Much faster," "more secure," "should work"
  — with no command, count, or measurement shown.
- **A verdict with no evidence.** "Looks secure" / "tests pass" with no file:line,
  no count, no output. Especially suspect when *suspiciously* clean.
- **Round-number metrics with no source.** A "50% improvement" that never shows
  the before, the after, or the command.
- **Phases skipped or collapsed.** Code appears with no plan; "security reviewed"
  with no findings and no verdict; a tester that clearly only read the plan; or a
  UI/UX change with no design contract and built-surface Sign-off.
- **N/A without a reason.** A Design stage disappears because the change was
  called "backend" even though a human-visible behavior, error, CLI, workflow, or
  accessibility surface changed.
- **One giant commit**, or `git add -A`, or unrelated files swept in, or a missing
  co-author tag.
- **The model rationalizes past a gate** it set itself ("technically this exceeds
  10% but it's probably fine") instead of asking.
- **Gates live only in the model.** No enforcement at all — not even a pre-push
  hook — so "I ran the tests" is the only thing standing between a bug and `main`;
  an interpreter/parser with only example tests and no fuzzer; a security pass
  with no deterministic scanner behind it.
- **Stale or fabricated references.** Cites a file/flag/line that doesn't exist, or
  re-states a doc that the code has since contradicted.

### 9.3 Audit questions to ask the model

When in doubt, make it show its work:

- *"Paste the exact command and its output that proves the tests ran and passed."*
- *"What did the security pass find, with file and line? What did it explicitly
  not review?"*
- *"Show the before and after numbers for that performance claim, and the command."*
- *"Show `git status` and the staged diff before you commit."*
- *"Which existing file did you model this on, and how does it match its patterns?"*
- *"What did you choose not to do, and why?"*

A model following the method answers these instantly from work it already did. A
model faking it scrambles — which is itself the signal.

---

## 10. Anti-patterns & hard-won lessons

- **Trusting a clean result from an unverified instrument.** The single most
  expensive failure. Confirm the verifier *ran* before believing what it reports.
  (The missing-`timeout`-binary false-green cost a whole session.)
- **Stale artifacts.** A test that exec's a week-old binary, or a doc that
  describes code as it *used* to be, produces confident wrong answers. Resolve the
  freshest build; keep docs in lockstep with code in the *same* change.
- **Optimizing before measuring.** Without a baseline you cannot prove a win, and
  you'll "optimize" noise. Baseline first, always.
- **Single-sample benchmarks.** Run-to-run variance is real; one sample lies in
  both directions. Median of several, same build system, before *and* after.
- **Sweeping in unrelated work.** Pre-grep the tree; if there are changes you
  didn't make, *exclude* them from your commits and say so. Never `git add -A`.
- **Letting the architect write code or the builder redesign.** Role bleed
  destroys the separation that makes the method work. Enforce it with tool scoping.
- **Scaling by file count instead of semantic risk.** Keep artifacts concise for
  a typo or comment, but still record proportionate architecture/impact,
  security, verification, and deployment-readiness checks. A one-line security,
  entitlement, dependency, parser, or release change is not trivial.
- **Deleting/overwriting without looking.** Before destroying anything you didn't
  create, read it — if it contradicts how it was described, surface that instead
  of proceeding.
- **Rationalizing past your own gate.** If you set a threshold, honor it: when
  reality exceeds it, that's a *decision point for the human*, not a paragraph of
  justification.
- **Approving an unseen interface.** Design Sign-off must inspect the actual built
  surface and representative states. When tooling cannot observe them, it returns
  a concrete verification checklist; it does not rubber-stamp the plan.

---

## 11. Appendices — copy-paste templates

### 11.1 Persona definition skeleton (`agents/<name>.md`)

```markdown
---
name: architect
description: Senior architect. Use after Design Mock for UI/UX work and first
  when Design is explicitly N/A. Explores the codebase,
  designs the approach, produces a file-by-file plan. Writes no code.
model: fable   # deep-cognition tier; fall back to opus when Fable is unavailable
tools: Read, Glob, Grep, WebSearch, WebFetch, Task
---

You are a Senior Software Architect in this ordered lifecycle:
Design Mock → Architecture → Design Review/Revision → Security (plan) → Build →
Security (code) → Design Sign-off → Test → Documentation → Deploy → Doc Validation.

Core principles:
1. Explore exhaustively before planning — read every file that could be affected;
   never assume, verify by reading.
2. Consistency over cleverness — match existing patterns and conventions.
3. Zero ambiguity — the Builder should never have to guess.

Your plan MUST include: Summary; Files to Create (path, purpose, signatures,
which existing pattern it follows); Files to Modify (path, exact location, change,
why); Data-model changes; Dependency order; Edge cases; Testing notes; and a final
"Conditions for Builder" section listing every security/correctness invariant.

NEVER write implementation code — only signatures and plan detail.
```

*(Make analogous files for `designer`, `security`, `builder`, and `tester` — each
with one job, narrowly scoped tools, and explicit "never do X" rules. The
Designer owns Mock, Review/Revision, and built-surface Sign-off; Security must end
both reviews with PASS / CONDITIONAL PASS / FAIL and cite `[SEVERITY] FILE:LINE →
fix`; the Tester owns functional, non-functional, regression, and applicable
fuzz/property/metamorphic evidence.)*

### 11.2 Operating-rules block for `CLAUDE.md`

```markdown
## Multi-Agent Pipeline (DEFAULT WORKFLOW)

Canonical sequence for every change:
Design Mock → Architecture → Design Review/Revision → Security (plan) → Build →
Security (code) → Design Sign-off → Test → Documentation → Deploy → Doc Validation.

Only the three Design stages may be N/A, only when there is no human-visible
behavior or interaction impact, and only with a written rationale. All other
stages run with depth proportionate to semantic risk. Novel threat surface gets
an explicit threat model, independently separated roles, deep testing, and
Security reruns after fixes.

Model assignments (pass explicitly every call). Design, Architecture, and Doc
Validation are the deep tier; all other phases are standard. Claude: Designer and
Architect → fable (fall back to the latest Opus when Fable is unavailable),
including as Doc Validation reviewers; Security, Builder, Tester, Documenter → the
latest sonnet. Codex: deep tier → GPT-5.6 Sol; standard tier → Terra (Luna
unassigned).

Every review returns PASS / CONDITIONAL PASS / FAIL. A conditional pass names
conditions, owner, and closing evidence. FAIL blocks; material changes rerun
affected downstream gates. All tests pass before an authorized deployment.
Deploy is also a readiness gate and does not create release authority: actually
deploy only when explicitly requested or when current repo instructions name the
command and target. Stage specific files (never `git add -A`), keep one logical
change per commit, and present design/plan summaries to the user when engaged.
```

### 11.3 Source-control rules

```markdown
- Tests pass → stage specific files → commit → authorized deploy or readiness evidence.
- Stage specific files — never `git add -A`.
- Never commit secrets (.env, keys, .p8) or build artifacts.
- One logical change per commit; clear imperative message.
- Co-author tag on every commit.
- main = stable; feature/<name> for larger work.
```

### 11.4 The compliance checklist (print this)

```
PLAN
[ ] Design applicability recorded; N/A has a no-UI/UX rationale
[ ] UI/UX change has a Design Spec grounded in existing design + acceptance criteria
[ ] Plan exists as text, with file paths + signatures + dependency order
[ ] "Conditions for Builder" lists security/correctness invariants
[ ] Design Review/Revision approved the plan before code was written
[ ] Plan summary was shown to me before code was written

SECURITY
[ ] Explicit PASS / CONDITIONAL PASS / FAIL verdict
[ ] Each finding: [SEVERITY] FILE:LINE → exact remediation
[ ] States what was reviewed and what was not
[ ] Confirms deterministic scans exist + are green (secret / SAST / dependency)

BUILD & TEST
[ ] Builder read the existing file before editing it (pattern match)
[ ] Build is green; output shown
[ ] UI/UX implementation received built-surface Design Sign-off
[ ] FULL test suite run; real count reported; assertions on content
[ ] Functional + regression matrix covers success/error/boundary/integration paths
[ ] Applicable non-functional tests cover performance/load/resource/a11y/concurrency
[ ] Parser/interpreter/format/protocol change → property/fuzz suite green (+ extended)
[ ] Adequacy reported where configured (coverage / mutation), not just pass-count
[ ] Performance/size claims have before+after numbers + the command
[ ] "It works" claims come from running the real thing

GATES (machine-enforced — at least a pre-push hook)
[ ] A pre-push hook (or required CI check) runs the full suite and blocks on failure
[ ] That gate actually ran for this change (not just self-reported)
[ ] Secret/SAST/dependency scanning runs somewhere (hook or CI), or is a noted gap
[ ] If CI exists: `main` requires the checks (branch protection on)

COMMIT
[ ] Specific files staged; `git status` shows nothing unexpected
[ ] One logical change; clear message; co-author tag
[ ] Docs updated in the same change
[ ] Unrelated/foreign changes were excluded and called out

DEPLOY / READINESS
[ ] Deploy target, command, authority, rollback, and post-deploy proof are explicit
[ ] If deployment is not authorized, deploy-ready evidence is delivered instead

JUDGMENT
[ ] Trade-offs exceeding a threshold were brought to me with numbers
[ ] Surprises were surfaced, not silently actioned
```

---

### Closing note

The method is not bureaucracy for its own sake. Each rule exists because its
absence produces a specific, recurring failure: anchoring, plausible-but-wrong
code, false-green verification, scope creep, lost intent. Adopt the pieces that
match your project's risk — lightly for thin technical work, fully for novel and
dangerous surface — but keep the spine intact: **written intent, separated
adversarial roles, and verification you can actually trust.** That spine is what
turns "the model wrote some code" into "a team shipped a verified change."
