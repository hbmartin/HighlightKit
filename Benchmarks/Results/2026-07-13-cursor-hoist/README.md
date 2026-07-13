# firstMatch cursor-walk local hoist — REJECTED & REVERTED

A post-step-31 `sample` profile attributed ~6% of JavaScript samples to
dynamic exclusivity enforcement (`swift_beginAccess` + `AccessSet::insert` +
TLS) and ~4% to `RuleMatchCache.firstMatch` itself. The candidate hoisted the
query loop's cursor walk onto a local with a single write-back, hypothesizing
the per-iteration `entry.cursor += 1` class-property modify access was the
cost:

```swift
var cursor = entry.cursor
let count = entry.starts.count
while cursor < count, entry.starts[cursor] < location { cursor += 1 }
entry.cursor = cursor
```

Verdict: **REJECTED**. On a quiet machine the change is a measured
regression — JavaScript **−1.395297%** (95% CI −1.722911…−1.066590, candidate
better in 1/15 pairs), TypeScript **−0.981534%** (−1.340462…−0.621300, 2/15),
Swift incremental latency **+0.525139%** (+0.043197…+1.009402) — with the
remaining scenarios neutral. The unconditional cursor store and hoisted count
evidently defeat codegen that the direct property walk gets for free. This is
the fourth exclusivity-motivated attack to measure neutral-to-negative in
this engine (steps 9, 10, 11, 32); the profile cost is real but does not
convert into wall-clock via this shape. The code was reverted to the direct
walk with a comment citing this campaign.

## Two campaigns, one valid

The first campaign (12:54:55–13:56:40 UTC, retained as
[runtime-raw-disturbed.json](runtime-raw-disturbed.json)) is **invalid**: a
`CoreSimulatorService` process consumed ~64% CPU during the window, violating
the quiet-machine precondition. Its intervals are an order of magnitude wider
than every other campaign in this series (TypeScript CI −17.9%…+8.3%) and its
baseline medians sit below the same binary's step-31 measurements. It is
retained for the record, not used for the verdict.

The clean re-run (14:00:39–14:02:11 UTC, [runtime-raw.json](runtime-raw.json),
`ps` verified no process above 30% CPU) produced interval widths consistent
with the rest of the series and is the basis of the rejection.

## Controlled inputs (clean re-run)

- Baseline executable (= step-31 candidate):
  `81dad2e01ce73a87e8e169111843c5f2a455022a58e68cfdfb1ba639ee1f97a0`
- Rejected candidate executable:
  `3cb20f800ec833a48a8c41ea6875267e16c0f90a19940d625ca666222ffa8aa8`
- Runtime real-Swift input (`Sources/HighlightKit/Core/HighlightEngine.swift`):
  `81e34ecbd94d1610e91b6a2a34a0f887810c63e969fa720a0aeddd6834ecde4f`

Machine: MacBook Pro Mac15,11, Apple M3 Max, 36 GB RAM, macOS 26.5.1
(Darwin 25.5.0), arm64; Swift 6.3.2. `hashes_stable: true` for both campaigns.

## Results (clean re-run)

| Scenario | Baseline median | Candidate median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| JavaScript throughput | 1.187051 MU/s | 1.169998 MU/s | **−1.395297%** | **−1.722911%…−1.066590%** | 1/15 | **slower** |
| TypeScript throughput | 0.842109 MU/s | 0.832910 MU/s | **−0.981534%** | **−1.340462%…−0.621300%** | 2/15 | **slower** |
| Swift incremental latency | 40.883383 µs/line | 41.195948 µs/line | **+0.525139%** | **+0.043197%…+1.009402%** | 3/15 | **slower** |
| Real-Swift throughput | 2.141441 MU/s | 2.140045 MU/s | +0.078556% | −0.259025%…+0.417280% | 6/15 | neutral |
| SQL control throughput | 2.058991 MU/s | 2.056695 MU/s | −0.156946% | −0.560251%…+0.247994% | 7/15 | neutral |
| JavaScript incremental latency | 35.302707 µs/line | 35.520061 µs/line | +0.356237% | −0.015786%…+0.729644% | 5/15 | neutral |
| All-space JS comment throughput | 18.907413 MU/s | 18.568204 MU/s | −2.127469% | −4.874178%…+0.698551% | 6/15 | neutral |

The compact CSV of the clean re-run's 105 paired observations:
[runtime-samples.csv](runtime-samples.csv).

## ThreadSanitizer note

The step-31 continuation-state change (dense `[UInt8]` hit counters carried
by generation-owned continuations) was re-verified under ThreadSanitizer in
this session: `swift test --sanitize=thread` over the stress and registry
suites (17 tests) passed with zero warnings, both with the (later-reverted)
hoist applied and on the final reverted tree.
