# P1 Benchmark Evidence — control-property-consistency

Per Condition 14: property-access workload, release build, `--benchmark-iterations 50`,
median of 3 runs, same build system, commands shown. Measured on this machine
(darwin, Xcode-beta toolchain) — used for before/after relative comparison; not
compared to the historical `docs/HypeTalkBenchmarkBaseline.md` absolute numbers,
which were recorded on different hardware/toolchain state.

## Commands

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build -c release --product hypetalk
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer .build/release/hypetalk --benchmark --benchmark-iterations 50
```

## BEFORE (pre-P1, working tree clean at `a3fb3e3`)

Three runs, `property-access` workload:

| Run | Execute Total ms | Execute Avg ms |
| --- | ---: | ---: |
| 1 | 237.322 | 4.746 |
| 2 | 237.005 | 4.740 |
| 3 | 241.088 | 4.822 |
| **Median** | **237.322** | **4.746** |

(Statements 70,250 / Expressions 280,400 / Property reads 35,000 / Property writes
17,550 / Loop iterations 17,500 — unchanged workload shape vs the documented
baseline; absolute ms differ from `docs/HypeTalkBenchmarkBaseline.md` due to
machine/toolchain drift since that baseline was recorded, not due to any code
change in this session.)

## AFTER (post-P1: registry gate inserted into both GET/SET switches)

The dev machine was noticeably noisier for this measurement (background
processes from the same session's earlier full-suite test run and release
build competing for CPU) — 9 runs were taken instead of 3 to get a stable
median; one clear outlier (a run at 344 ms, > 40% above the rest) is
reported rather than discarded, and the median is used specifically because
it is insensitive to that kind of single-run noise.

| Run | Execute Total ms |
| --- | ---: |
| 1 | 262.075 |
| 2 | 230.432 |
| 3 | 245.696 |
| 4 | 226.545 |
| 5 | 233.175 |
| 6 | 310.299 |
| 7 | 344.156 (outlier — background system noise) |
| 8 | 235.052 |
| 9 | 244.170 |
| **Median (9 runs)** | **244.170** |
| Median (first 3 runs only, for a strict apples-to-apples "3 runs" reading) | 245.696 |

## Verdict

| | Execute Total ms (median) |
| --- | ---: |
| BEFORE | 237.322 |
| AFTER | 244.170 |
| **Δ** | **+2.9%** |

Both the 9-run median (+2.9%) and the strict first-3-runs median (245.696 → +3.5%)
are well under the 5% regression budget (Condition 14). The added cost is the
one extra dictionary lookup (`PartPropertyRegistry.resolveGet`/`resolveSet`) per
property access on the hot path, exactly as anticipated in design.md's Risks
section ("+1 dictionary lookup per property access → benchmark gate"). No
further action needed; P1 does not block on performance.
