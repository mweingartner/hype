# P4 Benchmark + Size Evidence — control-property-consistency

Per design.md Condition 14 (property-access benchmark, >5% regression blocks) and
the Risks section's `-Osize` budget note. Recorded at the end of P4 (docs + final
conformance), the last work package of this change — this is the final, whole-change
evidence to sit alongside `benchmark-p1.md`'s P1-stage measurement.

Measured on this machine (darwin, Xcode-beta toolchain) — used for before/after
*relative* comparison; not compared to the historical
`docs/HypeTalkBenchmarkBaseline.md` absolute numbers, which were recorded on
different hardware/toolchain state (same caveat `benchmark-p1.md` already
documents).

Scope check: P2 (AI surface), P3 (Inspector), and P4 (docs, this package) touch
zero lines of `Interpreter.swift` — confirmed by `git diff --stat` against this
session's working tree touching only `HypeTalk-LLM-Context.md`,
`Sources/HypeCore/AI/HypeTalkGuide.swift`, `Tests/HypeCoreTests/HypeTalkGuideTests.swift`,
and `tasks.md`. So the only place a hot-path regression could have entered since
P1's own measurement is P1 itself (already measured and accepted at +2.9%); P4's
job here is to confirm the property-access path is still healthy on the finished
tree, not to re-attribute cost to any particular package.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build -c release --product hypetalk
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer .build/release/hypetalk --benchmark --benchmark-iterations 50
```

## Property-access workload — final tree (P1+P2+P3+P4 applied)

Three clean runs (machine quiesced after the release build finished):

| Run | Execute Total ms | Execute Avg ms |
| --- | ---: | ---: |
| 1 | 238.956 | 4.779 |
| 2 | 242.351 | 4.847 |
| 3 | 242.203 | 4.844 |
| **Median** | **242.203** | **4.844** |

An additional 8-run batch taken earlier in the same session, while other build/test
activity was still settling on the machine (same noise class `benchmark-p1.md`
documented for its own AFTER measurement), is included for robustness rather than
discarded:

| Run | Execute Total ms |
| --- | ---: |
| 1 | 268.765 |
| 2 | 249.052 |
| 3 | 255.767 |
| 4 | 253.100 |
| 5 | 249.886 |
| 6 | 249.714 |
| 7 | 253.897 |
| 8 | 248.159 |
| **Median (8 runs)** | **251.493** |

## Verdict — property-access

| Stage | Execute Total ms (median) | Δ vs pre-registry baseline (237.322 ms) | Δ vs P1's own AFTER (244.170 ms) |
| --- | ---: | ---: | ---: |
| BEFORE (pre-P1, `a3fb3e3`) | 237.322 | — | — |
| P1 AFTER (registry gate lands) | 244.170 | +2.9% | — |
| **P4 final (3 clean runs)** | **242.203** | **+2.1%** | **-0.8%** |
| P4 final (8-run robustness batch) | 251.493 | +6.0% | +3.0% |

The clean 3-run reading (the Condition 14 metric) is actually *faster* than P1's
own AFTER measurement — well inside noise, confirming P2/P3/P4 added no
additional cost to the property-access hot path (as expected: none of them touch
`Interpreter.swift`). Even the noisier 8-run batch reads +3.0% against P1's own
baseline, the correct comparison point since P1 already spent (and Design
accepted) the one-time registry-gate cost; it is under the 5% budget. **No
further action needed — P4 does not block on performance.**

## Release binary size delta (`-Osize` budget, design.md Risks)

Isolates exactly this package's (P4's) effect on the shipped `hypetalk` binary by
comparing the release build at the P3 HEAD commit (`ff882ef`, clean, no P4
changes) against the P4 working tree (this package's docs + test changes only).

```sh
# P3 HEAD (ff882ef) — git stash push the 3 P4-touched files, rebuild, measure, stash pop
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build -c release --product hypetalk
```

| Tree | `.build/release/hypetalk` size |
| --- | ---: |
| P3 HEAD (`ff882ef`) | 24,626,472 bytes |
| P4 (this package's docs + tests) | 24,642,984 bytes |
| **Δ** | **+16,512 bytes (+0.067%)** |

The entire delta is the `HypeTalkGuide.llmContext` string constant growing by
~6,350 characters (73,410 → 79,760, still under the 80 KB / 81,920-char guide
budget enforced by `HypeTalkGuideTests.guideStaysUnderBudget`) plus ordinary
string-literal/metadata overhead — not a code-path change. Well within any
reasonable `-Osize` budget; design.md's stated concern (Interpreter.o growth) is
inapplicable here since `Interpreter.swift` was not touched in P2, P3, or P4.

## Full suite (real counts)

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --no-parallel --filter HypeCoreTests --filter HypeTalkGuideTests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --no-parallel --filter HypeCLITests
```

- `HypeCoreTests` (+ `HypeTalkGuideTests`, same target): **3248 tests / 337 suites — all passed** (126.354s / 126.071s across two runs).
- `HypeCLITests`: **34 tests / 1 suite — all passed** (3.504s).
- Interpreter fuzz suites, both green: `Interpreter fuzz — no crash + determinism` and `Interpreter fuzz — property statements (registry dispatch)`; the pinned-seed regression test reports "No test cases found" (P1's `regressionSeeds` stayed empty — no fuzz failure has ever been found for this change).
- New P4 docs-conformance suite (`HypeTalkGuide + HypeTalk-LLM-Context.md — registry docs conformance`, 8 tests) — all passed: registry→guide coverage (non-legacy + legacy), guide→registry and .md→registry token resolution, .md-is-a-strict-subset-of-guide, and the three breaking-change-notes assertions (size pair, GET/SET posture, secure-masking set).
