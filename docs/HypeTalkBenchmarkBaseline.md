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

## Measurement Practice

- Run release benchmarks before and after each optimization.
- Keep iteration counts stable when comparing a branch to baseline.
- Record both timing deltas and diagnostic counter changes; timing without counter movement may indicate compiler/runtime noise rather than an interpreter improvement.
