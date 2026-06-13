# The Model-Paired Development Playbook

*How to build quality software by pairing with AI models — a reproducible recipe.*

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
- **Economical.** Tiering (below) means you spend the ceremony only where the
  threat/novelty justifies it; trivial work stays fast.

This is the difference between *"the model wrote some code"* and *"a disciplined
team shipped a verified change."*

---

## 2. The three pillars

Everything else is mechanics. The method rests on three pillars:

1. **Markdown as the shared brain** — written intent, written plans, written
   decisions. The model reads them before acting and writes them after.
2. **Separated adversarial personas** — architect, security, builder, tester, run
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

---

## 4. Pillar II — Separated adversarial personas

The heart of the method. Instead of one model doing everything, you run distinct
sub-agents, each with a single job, its own system prompt, and a deliberately
chosen model tier. **Separation creates the adversarial diversity that catches
what one pass cannot.**

### 4.1 The four personas

| Persona | Model tier | Tools | Single job | Why it's separate |
|---|---|---|---|---|
| **Architect** | **Opus** (strongest) | Read-only + web + Task | Explore exhaustively, design, produce a zero-ambiguity written plan. **Writes no code.** | Planning is the highest-leverage step; it deserves the strongest model and a context uncontaminated by implementation detail. |
| **Security** | Sonnet | Read-only + web | Find real vulnerabilities in the *plan*, then in the *code*. Cite file:line + severity + exact fix. | A reviewer who also wrote the code rubber-stamps it. A dedicated skeptic is incentivized to find holes. |
| **Builder** | Sonnet | Read/Edit/Write/Bash | Implement the plan faithfully, match existing patterns, keep the build green. | Implementation should *follow* the contract, not re-litigate the design mid-stream. |
| **Tester** | Sonnet | Read/Edit/Write/Bash | Read the real implementation, write white-box tests, run the **full** suite, fix until green. | A tester who only saw the plan tests the fantasy; one who reads the code tests reality. |

> **Model-tier nuance (important):** the persona definition files may default to
> one tier, but the operating rules **override the model per invocation** and you
> should pass it explicitly every time. In Hype: Architect → `opus`; Security,
> Builder, Tester → `sonnet`. Spend the expensive model where judgment matters
> most (design), and use the faster model for the well-specified execution roles.
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

### 4.3 The hand-off contract

Each persona's output is the next one's input, verbatim. The critical
augmentation the Hype workflow adds: the architect's plan ends with a **"Conditions
for Builder"** section enumerating every security/correctness invariant discovered
during planning. That embedded checklist *is* the design-stage security review for
routine work, and it travels with the contract so the builder cannot miss it.

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
- The **tester persona** is for *investigating failures* and writing
  **regression tests when a bug is found** — not for back-filling tests the
  builder should have written. Don't spawn a tester to test brand-new code; spawn
  it when something broke and you need to pin the behavior.
- Tests must assert **content**, not existence. "Returns non-nil" is not a test.
  "Returns `8` for `value(\"2 * (3+1)\")`" is.

### 5.2 The gates (non-negotiable invariants)

1. **All tests pass before deployment.** Not "the new tests" — the **full
   suite**, to catch regressions.
2. **The gate is machine-enforced.** CI runs the build + full suite + scans on
   every push/PR, and `main` requires those checks to pass (branch protection).
   "Tests pass" reported by the agent is a *claim*; a green required check is a
   *fact*. (See §5.7 for the deterministic-security and toolchain specifics.)
3. **In the full tier, code cannot reach the tester without passing security.**
4. **Stage specific files; never `git add -A`.** You commit what you reviewed.
5. **One logical change per commit**, with a clear message and co-author tag.
6. **One install/deploy at the end**, not after every phase.

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

### 5.7 Machine-enforced gates & deterministic security tooling

The personas *review*; CI *enforces*. Stand up, as required status checks on
`main`:

- **Build + full test suite (incl. the fuzz suite)** — the correctness gate.
- **Secret scanning** (e.g. gitleaks) — unambiguous; hard-fail on any finding.
- **SAST** (e.g. Semgrep source-pattern, or CodeQL when a build is available) —
  the deterministic backstop behind the security persona; it catches taint flows
  and dangerous patterns an LLM misses. Start informational, tune, then promote
  to blocking.
- **Dependency / SCA alerts** (e.g. Dependabot) — known-CVE and update tracking.

**A real-world wrinkle to plan for:** your CI runner must have your toolchain. If
the project pins a beta or unusual SDK (Hype targets a beta Swift/macOS SDK that
hosted runners don't carry), the build/test gate needs a **self-hosted runner**
(your dev machine), while the SDK-independent gates (secret scan, source-based
SAST, dependency alerts) run fine on hosted runners. Split them that way: get the
hosted gates green immediately, and wire the build/test gate to the self-hosted
runner (activated by a one-time registration + a repo flag) so it's ready and
correct even before the runner exists. Don't let a toolchain mismatch become an
excuse for *no* gate — run the SDK-independent ones now, and run the build/test
gate locally until the runner is live.

The LLM security persona is **necessary but not sufficient**: it should *confirm
these gates exist and are green*, not stand in for them.

---

## 6. The pipeline (the workflow)

Tie the pillars together into a repeatable sequence. **Match the ceremony to the
risk** — most work uses the Lite tier.

### 6.1 Choose the tier by *novelty of threat surface*, not file count

**Lite tier (default for most multi-file work):**

```
Pre-grep the tree → Architect (plan + "Conditions for Builder")
  → Builder (code + inline tests) → Security (code review)
  → run tests → one install → commit
```

**Full tier (only for genuinely novel risk):** trigger when the change involves
auth/credentials, network egress, file I/O on untrusted input, dynamic code
execution, sandboxing, cryptography, or any capability with **no analog already
shipped** in the codebase.

```
Architect → Security (plan) → Builder → Security (code) → Tester
  → one install → commit
```

The difference is the **plan-stage security pass** and a **dedicated tester
pass**. The Lite tier folds plan-stage security into the architect's "Conditions
for Builder" and lets the builder write tests inline — because the architectural
decisions for familiar work are already encoded in the predecessor you're
modeling after.

### 6.2 Skip the pipeline entirely for

Single-line fixes, typos, comment/config changes, and **additions that mirror an
existing pattern verbatim** (e.g. adding another control modeled on an existing
one — the design is already encoded in the predecessor; just edit directly).
Running a six-agent pipeline for a one-line fix is malpractice in the other
direction.

### 6.3 The gates between phases

- **After the architect:** present the plan summary to the human (when engaged);
  proceed only when the design is agreed. In full tier, security must PASS/
  CONDITIONAL-PASS the *plan* first.
- **After the builder:** security reviews the *actual code on disk* (it greps real
  files — it catches what plan review can't). 1–3 small findings? Fix inline. More
  than that, or anything critical/high? Send it back; don't sail past.
- **Before commit:** full suite green, specific files staged, message written.

### 6.4 Keep the human in the loop at decision points

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
  .github/
    workflows/
      ci.yml                # build + full test suite + fuzz (the correctness gate)
      secret-scan.yml       # gitleaks (hosted, SDK-independent)
      sast.yml              # Semgrep source-pattern SAST (hosted, SDK-independent)
    dependabot.yml          # dependency updates + CVE alerts
```

### 7.2 The files to write (in order)

1. **Persona definitions** (`agents/*.md`). Each is a markdown file with
   frontmatter (`name`, `description`, `model`, `tools`) and a system prompt that
   gives the persona one job and explicit rules. Use the appendix templates as a
   starting point. Pin the **tools** narrowly: the architect and security get
   **read-only** tools (Read/Grep/Glob/web) so they cannot accidentally write
   code; the builder and tester get Edit/Write/Bash.
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
5. **The CI gates** (`.github/`): the build/test workflow, secret scan, SAST, and
   Dependabot config. Make the SDK-independent ones (secret/SAST/deps) run on
   hosted runners immediately; wire the build/test gate to whatever runner has
   your toolchain (self-hosted if you pin a beta/unusual SDK). Then turn on
   **branch protection** so `main` requires the checks — that's the step that
   converts the workflow from advisory to enforced.

### 7.3 Configuration that matters

- **Model tiers, explicit per call.** Architect = strongest; security/builder/
  tester = a fast capable model. State the tier on every invocation — don't trust
  defaults.
- **Read-only tools for the thinkers.** Enforced tool scoping is what makes "the
  architect writes no code" a guarantee instead of a hope.
- **A real test runner and a real deploy command**, documented in the project
  `CLAUDE.md`, so every persona knows how to build, test, and ship.
- **Live interfaces where possible.** If your app exposes an automation/MCP
  interface, wire it in so verification can drive the *real* product, not a stub.

### 7.4 Cost & ergonomics

A full-tier run spends real tokens (six agents, exhaustive reads). That's the
point — you're buying defect-discovery you'd otherwise pay for in production. Keep
it economical by defaulting to Lite, skipping trivial work, and doing **one
install at the end** rather than rebuilding after every phase.

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
3. **Architect the plan (Opus, read-only).** Produce a phased plan — compatibility
   gaps, speed, size, watchOS — each phase with file paths, exact edits, expected
   wins, and a **"Conditions for Builder"** section (e.g. "dynamic `value()`
   evaluation must reuse the existing recursion-depth and byte-size caps").
4. **Implement in slices, each verified and committed.** Close the compatibility
   gaps (with inline fidelity tests); then the speed change (gate per-statement
   work to visible effects) — *proven* with publish-count and wall-clock numbers,
   and a correctness argument that the final render still flushes; then the size
   change (`-Osize`) — *measured* at −48% with a median-of-three CPU cost.
5. **Verify the hard claim empirically.** "watchOS-capable" wasn't asserted — a
   throwaway sub-agent and then a committed script **compiled the interpreter
   kernel for the watchOS triple**, proving 192/214 source files build for watch
   and naming the exact device-only files that don't.
6. **Surface the trade-off.** The `-Osize` CPU cost exceeded the pre-agreed gate,
   so the decision went **back to the human** with the numbers — not quietly
   absorbed.
7. **Land it cleanly.** Full suite green (3,026 tests, serial for determinism);
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

- **The architect's plan is specific.** File paths, type signatures, dependency
  order, edge cases, and a **"Conditions for Builder"** section. Not prose like
  "we'll update the parser to handle this."
- **Security cites coordinates.** Each finding has `[SEVERITY] FILE:LINE →
  exact remediation`, and an explicit **PASS / CONDITIONAL PASS / FAIL** verdict.
  It names what it *did* review, and admits what it *couldn't*.
- **Tests are real and counted.** The output shows a concrete suite result
  (*"3,026 tests passed"*), run on the **full** suite, with assertions on content.
- **Claims carry evidence.** Performance/size statements come with the command and
  before/after numbers; "it works" comes with output from running the real thing.
- **Commits are clean.** *Specific* files staged, one logical change each, clear
  message, co-author tag. `git status` after shows nothing unexpected swept in.
- **Surprises are surfaced, not actioned.** When the model finds something it
  didn't expect (unrelated changes in the tree, a doc that contradicts the code),
  it *reports* it rather than silently "fixing" it.
- **Trade-offs come to you.** Genuine judgment calls that exceed a threshold are
  raised with options and a recommendation.
- **The gate is the machine.** CI ran the suite + scans and is green (a required
  check, not a screenshot of a local run); parser/format changes show the fuzz
  suite green; the security pass *confirms* the deterministic scans, not just its
  own read.

### 9.2 Red flags (compliance theater or corner-cutting)

- **Adjectives instead of numbers.** "Much faster," "more secure," "should work"
  — with no command, count, or measurement shown.
- **A verdict with no evidence.** "Looks secure" / "tests pass" with no file:line,
  no count, no output. Especially suspect when *suspiciously* clean.
- **Round-number metrics with no source.** A "50% improvement" that never shows
  the before, the after, or the command.
- **Phases skipped or collapsed.** Code appears with no plan; "security reviewed"
  with no findings and no verdict; a tester that clearly only read the plan.
- **One giant commit**, or `git add -A`, or unrelated files swept in, or a missing
  co-author tag.
- **The model rationalizes past a gate** it set itself ("technically this exceeds
  10% but it's probably fine") instead of asking.
- **Gates live only in the model.** No CI, or "I ran the tests" with no required
  check behind it; an interpreter/parser with only example tests and no fuzzer; a
  security pass with no deterministic scanner behind it.
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
- **Ceremony for trivial work.** A six-agent pipeline for a typo wastes tokens and
  trust. Tier honestly; skip when the predecessor already encodes the design.
- **Deleting/overwriting without looking.** Before destroying anything you didn't
  create, read it — if it contradicts how it was described, surface that instead
  of proceeding.
- **Rationalizing past your own gate.** If you set a threshold, honor it: when
  reality exceeds it, that's a *decision point for the human*, not a paragraph of
  justification.

---

## 11. Appendices — copy-paste templates

### 11.1 Persona definition skeleton (`agents/<name>.md`)

```markdown
---
name: architect
description: Senior architect. Use FIRST for any feature. Explores the codebase,
  designs the approach, produces a file-by-file plan. Writes no code.
model: opus
tools: Read, Glob, Grep, WebSearch, WebFetch, Task
---

You are a Senior Software Architect — phase 1 of Architect → Builder → Tester.

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

*(Make analogous files for `security`, `builder`, `tester` — each with one job,
read-only vs. write tools as appropriate, and explicit "never do X" rules. The
security persona must end every review with a PASS / CONDITIONAL PASS / FAIL
verdict and cite `[SEVERITY] FILE:LINE → fix` for each finding.)*

### 11.2 Operating-rules block for `CLAUDE.md`

```markdown
## Multi-Agent Pipeline (DEFAULT WORKFLOW)

Two tiers, chosen by novelty of threat surface (not file count).

Lite tier (default): pre-grep the tree → Architect (plan + "Conditions for
Builder") → Builder (code + inline tests) → Security (code) → run tests →
one install → commit.

Full tier (auth, network egress, untrusted I/O, dynamic exec, sandboxing,
crypto, or any capability with no analog already shipped):
Architect → Security (plan) → Builder → Security (code) → Tester → install → commit.

Model assignments (pass explicitly every call): Architect → opus; Security,
Builder, Tester → sonnet.

Skip entirely for: one-line fixes, typos, comments, config, and additions that
mirror an existing pattern verbatim.

Invariants: code-stage security review is mandatory in both tiers; all tests pass
before deploy; in full tier code cannot reach the Tester without passing Security;
stage specific files (never `git add -A`); one logical change per commit; one
install at the end; present the plan summary to the user before proceeding.
```

### 11.3 Source-control rules

```markdown
- Tests pass → stage specific files → commit → deploy.
- Stage specific files — never `git add -A`.
- Never commit secrets (.env, keys, .p8) or build artifacts.
- One logical change per commit; clear imperative message.
- Co-author tag on every commit.
- main = stable; feature/<name> for larger work.
```

### 11.4 The compliance checklist (print this)

```
PLAN
[ ] Plan exists as text, with file paths + signatures + dependency order
[ ] "Conditions for Builder" lists security/correctness invariants
[ ] Plan summary was shown to me before code was written

SECURITY
[ ] Explicit PASS / CONDITIONAL PASS / FAIL verdict
[ ] Each finding: [SEVERITY] FILE:LINE → exact remediation
[ ] States what was reviewed and what was not
[ ] Confirms deterministic scans exist + are green (secret / SAST / dependency)

BUILD & TEST
[ ] Builder read the existing file before editing it (pattern match)
[ ] Build is green; output shown
[ ] FULL test suite run; real count reported; assertions on content
[ ] Parser/interpreter/format/protocol change → property/fuzz suite green (+ extended)
[ ] Adequacy reported where configured (coverage / mutation), not just pass-count
[ ] Performance/size claims have before+after numbers + the command
[ ] "It works" claims come from running the real thing

GATES (machine-enforced)
[ ] CI ran the build + full suite (not just self-reported) and is green
[ ] Secret scan + SAST + dependency checks ran and are green/triaged
[ ] `main` requires these checks (branch protection on)

COMMIT
[ ] Specific files staged; `git status` shows nothing unexpected
[ ] One logical change; clear message; co-author tag
[ ] Docs updated in the same change
[ ] Unrelated/foreign changes were excluded and called out

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
