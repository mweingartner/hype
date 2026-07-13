# Model-Paired Development — Protocol Doctrine

This is the canonical doctrine mpd enforces. mpd installs it into every project
it initializes (`.mpd/directives/protocol.md`); edit that copy to adapt it. The
per-persona directives live alongside it in `.mpd/directives/personas/`.

## The idea

Model-Paired Development pairs a fixed sequence of **adversarial personas** —
each with a distinct lens and its own model — against every non-trivial change,
and backs the human-fallible parts with **deterministic, machine-enforced
gates**. The goal is *correct* code, not merely *working* code. mpd is the
harness-agnostic engine: it orders the phases, names the persona and model for
each, and refuses to advance on an unmet gate.

## The pipeline

```
Design Mock → Architecture → Design Review → Security (plan) → Build →
Security (code) → Design Sign-off → Test → Documentation → Deploy → Doc Validation
```

A phase is skipped only when it genuinely has no bearing on the change — never to
save time:

- **Design** phases (Mock, Review, Sign-off) run only for changes with a UI/UX
  surface (`mpd begin --ui`).
- **Documentation** phases (Documentation, Doc Validation) run only for feature
  changes that alter functional behavior; defect fixes (`--fix`) and
  non-functional chores (`--chore`) skip them.
- Everything else is mandatory. Small or docs-only changes use concise,
  proportionate artifacts; size or familiarity never bypasses a gate.

## Gates are machine-enforced, not self-reported

Every gate ends **PASS**, **CONDITIONAL PASS**, or **FAIL**. A conditional pass
records open conditions (owner + closing evidence) that block archive until
resolved (`mpd resolve`). A FAIL blocks; a material change returns to the
earliest affected phase and invalidates downstream approvals.

Prefer the machine over the persona's word:

- **Build/Test** gates re-run the configured test command and require a real,
  non-zero pass count. A clean result from an unverified runner is a red flag.
- **Security (code)** runs secret scanning (built-in floor; gitleaks/Semgrep when
  present) and refuses on any finding.
- **Documentation** structurally checks the doc (all sections, no placeholders).
- **Deploy** runs the configured deploy command and refuses on failure.
- **Archive** refuses on any non-PASS gate or open condition, and previews the
  spec + doc merge before applying.

Parsers, interpreters, serializers, codecs, and wire protocols get
property/fuzz/metamorphic tests (seeded + reproducible), not just example tests.
Performance/size claims need before+after numbers, median of several runs, same
build, command shown. **Verify your verification** — confirm the test command
actually executed tests.

## Rigor escalation — novel threat surface

When a change involves auth/credentials, network egress, file I/O on untrusted
input, dynamic code execution, sandboxing, cryptography, or a feature with no
analog already shipped: run the security phases at full depth (explicit threat
model at plan stage, deep code audit at code stage) and do **not** fix findings
inline — re-run Security (code) after every fix. Code cannot reach Test without a
passing Security (code).

## Persona models

Each persona runs under a model resolved per harness. mpd carries built-in tier
defaults — the judgment/creative planning and validation phases (Design,
Architecture, Doc Validation) get the strongest model; the execution/synthesis/
review phases (Security, Build, Test, Documentation) get the standard model — and
lets you override per persona in `.mpd/config.json` (`models`, `model_fallbacks`)
as models evolve. `mpd next --harness <h>` prints the resolved model per phase.

## Working principles (apply proportionately)

- **Speak the domain's language.** Use the user's exact terms in code, specs,
  and commits. Reconcile "false cognates" before writing code.
- **Promote implicit rules into named concepts.** A buried guard clause the user
  would describe in a sentence is a missing concept — name it.
- **Bounded contexts at every seam.** Translate at boundaries with external
  systems; don't import their types into the core.
- **Refactor toward deeper insight.** The first model is usually wrong; friction
  is a signal, not just nuisance.
- **Supple design.** Intention-revealing names; side-effect-free functions where
  possible; assertions for invariants; factor along the domain's natural seams.

DDD-grade modeling is a tax that pays back in complex domains and bankrupts
simple ones. Default to lighter approaches; reach for the heavy patterns only
when complexity demands it.
