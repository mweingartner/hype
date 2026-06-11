# HypeTalk Benchmark Baseline

Date: 2026-05-23

This document records the initial HypeTalk CLI benchmark framework baseline and the first optimization plan derived from the instrumented execution diagnostics.

## Benchmark Command

Debug validation:

```sh
swift build --product hypetalk
.build/debug/hypetalk --benchmark --benchmark-iterations 10
```

Release baseline:

```sh
swift build -c release --product hypetalk
.build/release/hypetalk --benchmark --benchmark-iterations 50
```

## Workloads

- `looping-and-expressions`: arithmetic, repeated conditionals, chunk access, string concatenation, and counted loops.
- `property-access`: field creation, part property mutation, field text writes, field text reads, and part lookup by object reference.
- `callbacks`: callback-style `ask ai ... with message` dispatch through a stub runtime with no external service dependency.
- `realistic-mix`: combined field and button creation, property writes, property reads, text mutation, conditionals, looped game-like state updates, and periodic callback-style AI requests.

## Release Baseline

Measured with `.build/release/hypetalk --benchmark --benchmark-iterations 50`.

| Workload | Parse ms | Execute Total ms | Execute Avg ms | Statements | Expressions | Property Reads | Property Writes | Loop Iterations | Callback Requests |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| looping-and-expressions | 0.348 | 178.418 | 3.568 | 112,700 | 337,750 | 0 | 0 | 37,500 | 0 |
| property-access | 0.083 | 194.734 | 3.895 | 70,250 | 280,400 | 35,000 | 17,550 | 17,500 | 0 |
| callbacks | 0.041 | 39.500 | 0.790 | 25,150 | 62,750 | 0 | 0 | 12,500 | 12,500 |
| realistic-mix | 0.079 | 392.852 | 7.857 | 161,100 | 622,400 | 40,000 | 20,000 | 20,000 | 400 |
| total | - | 805.504 | - | 369,200 | 1,303,300 | 75,000 | 37,550 | 87,500 | 12,900 |

### Release Hot Counters

- `looping-and-expressions`
  - Hot statements: `put=37600`, `addTo=37500`, `ifThenElse=37500`, `repeatWith.iteration=37500`, `repeatWith=50`
  - Hot expressions: `literal=135150`, `variable=90050`, `binary=75000`, `chunk=30000`, `stringConcat=7500`
- `property-access`
  - Hot statements: `put=52550`, `set=17550`, `repeatWith.iteration=17500`, `createField=50`, `repeatWith=50`
  - Hot expressions: `literal=140250`, `variable=35050`, `objectRef=35000`, `propertyAccess=35000`, `binary=17500`
  - Hot property reads: `left=17500`, `text=17500`
- `callbacks`
  - Hot statements: `put=12550`, `askAI=12500`, `repeatWith.iteration=12500`, `repeatWith=50`, `returnValue=50`
  - Hot expressions: `literal=25100`, `variable=12550`, `it=12500`, `spacedConcat=12500`, `empty=50`
- `realistic-mix`
  - Hot statements: `put=80500`, `ifThenElse=40000`, `addTo=20000`, `repeatWith.iteration=20000`, `set=20000`
  - Hot expressions: `literal=281050`, `variable=120450`, `binary=60000`, `spacedConcat=40400`, `objectRef=40000`
  - Hot property reads: `name=20000`, `text=20000`

## Debug Baseline

Measured with `.build/debug/hypetalk --benchmark --benchmark-iterations 10`.

| Workload | Parse ms | Execute Total ms | Execute Avg ms | Statements | Expressions | Property Reads | Property Writes | Loop Iterations | Callback Requests |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| looping-and-expressions | 0.581 | 96.684 | 9.668 | 22,540 | 67,550 | 0 | 0 | 7,500 | 0 |
| property-access | 0.115 | 99.197 | 9.920 | 14,050 | 56,080 | 7,000 | 3,510 | 3,500 | 0 |
| callbacks | 0.080 | 15.338 | 1.534 | 5,030 | 12,550 | 0 | 0 | 2,500 | 2,500 |
| realistic-mix | 0.180 | 190.032 | 19.003 | 32,220 | 124,480 | 8,000 | 4,000 | 4,000 | 80 |
| total | - | 401.252 | - | 73,840 | 260,660 | 15,000 | 7,510 | 17,500 | 2,580 |

## Initial Optimization Plan

1. Cache object and property resolution within a handler execution.
   - The property workloads show high `objectRef` and `propertyAccess` counts.
   - Start with repeated part lookups by object type plus identifier for stable document snapshots during a handler.

2. Reduce expression evaluator overhead for dominant expression kinds.
   - `literal`, `variable`, `binary`, and `spacedConcat` dominate all workloads.
   - Prioritize avoiding repeated lowercasing and repeated dictionary lookups in tight loops.

3. Optimize `repeatWith` loop variable mutation.
   - `repeatWith.iteration` is a top counter in every non-trivial workload.
   - Consider pre-normalizing the loop variable key and using a lower-overhead local update path.

4. Improve repeated string append paths.
   - Realistic scripts often use `put ... after` to build logs or buffers.
   - Investigate using a buffer-oriented path internally when repeated appends target the same local or `it`.

5. Keep callback dispatch lower priority for the first optimization pass.
   - Callback setup is measurable but currently much cheaper than property and expression-heavy workloads.
   - Revisit after expression/property optimizations or when benchmarking real async runtime dispatch instead of the stub runtime.

## Phase 1 Optimization Results

Implemented a handler-local part lookup cache in `Environment` for repeated object-type plus identifier resolution. The cache is invalidated on part creation, deletion, and part `name` mutation. Also pre-normalized the `repeat with` loop variable key so each loop iteration avoids lowercasing that variable name.

Measured with `.build/release/hypetalk --benchmark --benchmark-iterations 50`.

| Workload | Baseline Execute Total ms | Phase 1 Execute Total ms | Delta |
| --- | ---: | ---: | ---: |
| looping-and-expressions | 178.418 | 184.022 | +3.1% |
| property-access | 194.734 | 154.501 | -20.7% |
| callbacks | 39.500 | 37.458 | -5.2% |
| realistic-mix | 392.852 | 329.107 | -16.2% |
| total | 805.504 | 705.088 | -12.5% |

The diagnostic counters stayed stable, so the timing changes are attributable to lower interpreter overhead rather than changed workload behavior. The pure loop workload regressed slightly; the next phase should prioritize variable/expression fast paths and verify that the lookup cache does not add measurable overhead to scripts that do not touch parts.

Focused validation:

```sh
swift build --product hypetalk
.build/debug/hypetalk --benchmark --benchmark-iterations 10
swift build -c release --product hypetalk
.build/release/hypetalk --benchmark --benchmark-iterations 50
swift test --filter HypeTalk
```

### Next Phase

1. Reduce variable-expression overhead.
   - Avoid repeated lowercasing in `.variable` evaluation by normalizing once per lookup and using normalized environment helpers.
   - Replace `env.locals.keys.contains(key)` with direct dictionary lookup checks on the hot system-property fallback path.

2. Re-check pure loop performance after the variable fast path.
   - The phase-one cache should mostly be cold for `looping-and-expressions`; if the regression remains, benchmark with and without the cache field in `Environment` to isolate dictionary storage overhead from normal run noise.

3. Consider a positive-only object reference cache for `resolveObjectRef`.
   - Keep this behind the same invalidation rules as the part index cache.
   - Prioritize field/button/card references because they dominate the current benchmark mix.

## Phase 2 Idle Hook Results

Implemented an idle-focused runtime pass for animation frame consistency:

- Added a successful-parse cache for repeated `MessageDispatcher` dispatches. This targets `idle` and `frameUpdate`, where the same scripts are dispatched every tick/frame.
- Changed `StackRuntime.dispatchIdleBurst` to enqueue the entire burst before processing instead of starting the queue once per target.
- Coalesced document-change notifications for multi-target runtime batches.
- Changed the canvas idle timer from `0.5s` to `1 / 60s` and cached idle target discovery so frames do not rescan every script unless the card/script signature changes.
- Added an `idle-hook-burst` benchmark workload that dispatches idle to 12 animated parts through `StackRuntime`.

Measured with `.build/release/hypetalk --benchmark --benchmark-iterations 50`.

| Workload | Execute Total ms | Execute Avg ms | Frame Budget Share |
| --- | ---: | ---: | ---: |
| idle-hook-burst | 10.314 | 0.206 | 1.2% of 16.667 ms |

The idle benchmark mutates 12 button parts via `on idle` handlers that read and write `the left of me`. This measures the runtime dispatch path used by the app idle hook, not just raw interpreter execution.

Focused validation:

```sh
swift build
swift build -c release --product hypetalk
.build/release/hypetalk --benchmark --benchmark-iterations 50
swift test --filter EventDispatchTests
```

## Phase 2.0 — Extended Harness Baseline (pre-optimization)

Date: 2026-06-11

Added `RealisticBenchmarkRuntime`, four micro-benchmark cases, and the production-wall-clock column to establish a measurable baseline before the upcoming `publishDocument` / frame-pacing optimization.

### Harness Extensions

**RealisticBenchmarkRuntime** — a new `ScriptRuntimeProviding` test seam that mirrors `BenchmarkRuntime` for all protocol methods except `publishDocument`, which:
1. Increments an atomic `publishCount` counter.
2. Awaits `Task.sleep(nanoseconds: frameDelayNanos)` — `16_666_667` ns (≈ 16.67 ms, one 60 Hz frame) in production mode, or `0` for pure-CPU mode.

This makes the `publishDocument` cost (previously hidden by the no-op `BenchmarkRuntime`) directly measurable as the **production wall-clock** column.

**Micro-benchmark cases** — four new focused workloads appended to the full suite:

| Case | Purpose |
| --- | --- |
| `micro-arith-loop` | Tight `add`/compare in `repeat with i from 1 to 2000` — isolates variable/expression fast path |
| `micro-chunk-churn` | 600 iterations of `word N of`, `char 1 of`, `item N of` on a 50-word container — isolates chunk overhead |
| `micro-property-churn` | 500 iterations of `set/get left` and `set/get text` on a single field — isolates property dispatch |
| `micro-idle-game-loop` | `idle-hook-burst` extended to 48 animated parts — stresses the StackRuntime dispatch and coalescing path |

### Benchmark Commands for This Baseline

Pure-CPU regression (fast; same as previous phases):

```sh
swift build -c release --product hypetalk
.build/release/hypetalk --benchmark --benchmark-iterations 50
```

Production-wall-clock measurement (slow; ~16.67 ms sleep per `publishDocument` call):

```sh
swift build -c release --product hypetalk
.build/release/hypetalk --benchmark --benchmark-iterations 3 --benchmark-frame-delay-nanos 16666667
```

> Use a lower iteration count for the wall-clock run to keep total time reasonable. The pure-CPU run at 50 iterations is still the canonical regression number; the wall-clock run shows the absolute cost of `publishDocument` per workload.

### Pre-Optimization Results (publishes = statements)

Before the gating optimization, `executeStatementAndPublish` called
`publishDocument` after **every** statement, so the pre-optimization publish
count equals the statement count and the production wall-clock is
`statements × 16.67 ms`. The table below is measured at `--benchmark-iterations
10`, `--benchmark-frame-delay-nanos 0` (publish counts are exact; the sleep is
elided so the run is fast — wall-clock is computed as `publishes × 16.67 ms`).

| Workload | statements (= pre-opt publishes) | pre-opt wall-clock |
| --- | ---: | ---: |
| looping-and-expressions | 22,540 | ~376 s |
| property-access | 14,050 | ~234 s |
| callbacks | 5,030 | ~84 s |
| realistic-mix | 32,220 | ~537 s |
| micro-arith-loop | 40,050 | ~668 s |
| micro-chunk-churn | 24,040 | ~401 s |
| micro-property-churn | 30,050 | ~501 s |

> **How to read this table:** `pure-CPU total ms` comes from `BenchmarkRuntime` (no-op `publishDocument`) and is the same number as the existing release baseline. `production wall-clock ms` comes from `RealisticBenchmarkRuntime(frameDelayNanos: 16_666_667)` — it shows how much total time a workload would take in a live app including the per-statement frame-pacing sleep. `publishes` is the `publishCount` from `RealisticBenchmarkRuntime`.

## Phase 2.1 — publishDocument visible-effect gating (speed)

Date: 2026-06-11. Commit: `hypetalk: gate per-statement publish on visible effect`.

The interpreter published the whole document after every statement, and
`StackRuntime.publishDocument` slept 16.67 ms unconditionally — a one-frame tax
on every statement including pure-compute hot paths. The gate
(`statementProducesVisibleEffect`) now publishes only on statements that mutate
rendered content (field/part writes, `set`, `show`/`hide`, `go`, `visual`, …);
pure-compute statements (variable `put`, `get`, arithmetic on a variable, control
flow) only `Task.yield()`. `lock screen` suppresses all mid-handler publishing;
the terminal document flush in `processQueue`/`apply()` still guarantees final
state renders. Animations/transitions/`wait` already pace themselves at their
call sites, so removing the blanket sleep changes no visible timing.

Publishes after gating (`--benchmark-iterations 10`, `--benchmark-frame-delay-nanos 0`):

| Workload | pre-opt publishes | post-gate publishes | wall-clock reduction |
| --- | ---: | ---: | ---: |
| looping-and-expressions | 22,540 | **0** | ∞ (pure compute) |
| micro-arith-loop | 40,050 | **0** | ∞ (pure compute) |
| micro-chunk-churn | 24,040 | **0** | ∞ (pure compute) |
| property-access | 14,050 | 7,020 | 2.0× |
| micro-property-churn | 30,050 | 10,020 | 3.0× |
| realistic-mix | 32,220 | 8,100 | 4.0× |
| callbacks | 5,030 | 2,500 | 2.0× |

A tight 2000-iteration arithmetic loop that previously cost ~67 s of wall-clock
frame sleeps per run (each statement paying 16.67 ms) now runs at CPU speed
(~2 ms). Pure-CPU `execute total` is essentially unchanged (gating removes
publishes, not interpreter work). Regression coverage:
`Tests/HypeCoreTests/InterpreterPublishGatingTests.swift`.

## Phase 3 — `-Osize` on HypeCore (size)

Date: 2026-06-11. Commit: `hypetalk: -Osize + watchOS-portable interpreter kernel`.

HypeCore now builds with `-Osize` in release (`.unsafeFlags` gated to release;
debug stays `-Onone`). Measured on the interpreter object (Xcode-beta, same
build system, `size -m … | __text`):

| Optimization | Interpreter.o `__text` |
| --- | ---: |
| `-O` (default) | 1,635,836 B (~1.56 MB) |
| `-Osize` | 843,932 B (~824 KB) |

**−48% __text** — far beyond the usual 10–20% because the interpreter is
inlining-heavy under `-O`. The trade is a few-percent pure-CPU cost on
compute micro-benchmarks (median of 3 release runs, `-O` → `-Osize`):

| Workload | `-O` ms | `-Osize` ms | Δ |
| --- | ---: | ---: | ---: |
| looping-and-expressions | 54.2 | 55.4 | +2.2% |
| callbacks | 10.7 | 11.2 | +5.0% |
| micro-arith-loop | 88.3 | 93.4 | +5.8% |
| micro-chunk-churn | 127.2 | 137.4 | +8.1% |
| micro-property-churn | 84.2 | 93.2 | +10.6% |
| realistic-mix | 93.5 | 105.5 | +12.8% |
| property-access | 37.8 | 45.8 | +21.0% |

The regression concentrates on property access (`-Osize` de-inlines the large
`evaluateProperty`). It lands on a pure-CPU path that production never hits — the
Phase 2.1 frame-paced publish gate dominates real wall-clock — so the trade was
accepted for the mobile/watch footprint goal. A future static-dictionary dispatch
for `evaluateProperty`/`evaluateBuiltIn` is the natural way to claw back the
property-access CPU.

## Phase 5 — watchOS portability proof (footprint)

Date: 2026-06-11. Same commit as Phase 3.

`scripts/watch-kernel-probe.sh` compiles HypeCore for the
`arm64-apple-watchos10.0-simulator` triple with only documented device-only leaf
files excluded. Result: **192 of 214 HypeCore files compile for watchOS** — the
HypeTalk interpreter and ~90% of the library are watch-portable. The 22 excluded
leaves are audio engines (AudioKit/AVFoundation), 3D loaders (SceneKit/ModelIO),
the classic `.stak` C importer (CStackImport), the AppKit/SwiftUI view layer, and
the AI document-tooling cluster — none referenced by the interpreter core. Two
in-place guards made it possible: `AppleMusicProvider` (ApplicationMusicPlayer)
and `RuntimeAIProvider` (FoundationModels) are now `#if … && !os(watchOS)`.

```sh
scripts/watch-kernel-probe.sh   # exit 0 = interpreter kernel builds for watchOS
```

## Deferred optimization opportunities

Scoped and intentionally deferred (each is a self-contained follow-on pass):

1. **Static-dictionary dispatch for `evaluateProperty` / `evaluateBuiltIn`.** The
   property/builtin switches are large `case "name":` chains. A `static let`
   `[String: handler]` map is O(1) and is the natural way to claw back the
   `-Osize` property-access CPU regression (Phase 3). Risk: every alias arm
   (multi-name cases) must map to the same handler — add a test enumerating all
   known property/builtin names so a dropped alias fails loudly.

2. **Tagged value model (`HValue`) — Stage A.** `Value` is `typealias String`, so
   arithmetic and comparison round-trip through `String` on every operation.
   Introducing an interpreter-internal `enum HValue { case number/bool/string/empty }`
   for `evaluateBinary` and the math builtins (Double path, `.asString` only at the
   `evaluate(...) -> Value` boundary) removes those round-trips for a ~1.5–2.5×
   compute-CPU win and lower allocation — relevant to the watch footprint. The
   anticorruption boundary is hard: `HValue` must live ONLY inside arithmetic/
   comparison eval; `textContent`, `scriptGlobals`, `env` storage, and all provider
   signatures stay `String`. Reuses the Phase 1 numeric-vs-text `compare` semantics.

3. **Full watchOS target (multi-module split).** Separate the interpreter kernel
   (`Script/` + the Foundation-only Models/provider subset) into its own SwiftPM
   target so a watch app can depend on it without the AppKit view layer. The
   probe (`scripts/watch-kernel-probe.sh`) already proves the source is ready; the
   cost is updating imports across the ~200 sites that currently `import HypeCore`.

## Measurement Practice

- Run release benchmarks before and after each optimization.
- Keep iteration counts stable when comparing a branch to baseline.
- Record both timing deltas and diagnostic counter changes; timing without counter movement may indicate compiler/runtime noise rather than an interpreter improvement.
- After each optimization wave, append a row to the Phase 2.0 results table using the same iteration count and record both the pure-CPU and production-wall-clock deltas.
