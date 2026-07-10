# Registry generation publication cache v2 — REJECTED

This directory records the formal v2-final candidate. The registry-specific
goals succeeded, including the 32-reader path that rejected mutex v1, but two
document-throughput controls regressed with 95% intervals wholly below zero:

1. JavaScript throughput: **−1.435524%**
   (95% CI **−2.289676%…−0.573905%**; candidate won 1/15 pairs).
2. TypeScript throughput: **−0.898650%**
   (95% CI **−1.499526%…−0.294109%**; candidate won 2/15 pairs).

Verdict: **REJECTED, not adopted**. Registry correctness and targeted latency
wins do not authorize a resolved loss on a primary highlighting path.

## Controlled inputs

Both arm64 executables use the same benchmark host, relinked against separate
frozen release object/module sets. They are controlled measurement artifacts,
not substitutes for a normal package release build.

SHA-256 values, stable before and after both campaigns:

- Benchmark host source:
  `540fab4526506bf2f7f0ccce6c964f85c8973b980b94af79be82b63f25a1d6cb`
- Baseline executable:
  `5b3ce1cd5a04952f7b5647f26ac63e517a57962148f778ca38715b436d27a766`
- Rejected v2-final executable:
  `cc4f84c2c713a934ac6ad1ba64b5f9932b1ec10bfdd3ba608b9b61ed4eb80422`
- V2 `LanguageRegistry.swift` source:
  `2b0c58da397016ca7c4c16aa9dd8959bb847e0d2408fdb85b122ed8d3f6d033c`
- Runtime real-Swift input:
  `c625eb052f1f06fe167c5133dff67c76a471ffe796c7970d3c1d920ae56f8e2e`

Machine: MacBook Pro Mac15,11, Apple M3 Max, 36 GB RAM, macOS 26.5.1,
arm64; Swift 6.3.2. `pmset` reported no thermal or performance warning, and no
Swift build, profiler, or other CPU-intensive process ran during sampling.
Registry sampling ran from 2026-07-10 10:30:24–10:31:12 UTC; runtime controls
followed directly at 10:31:21–10:32:55 UTC.

## Reproduction

From the repository root, using frozen executables linked from the same host:

```sh
BASE=/path/to/frozen-baseline/highlight-bench
CANDIDATE=/path/to/frozen-v2-candidate/highlight-bench
OUT="${TMPDIR:-/tmp}/highlight-registry-v2-ab"

python3 Benchmarks/paired_registry_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --output "$OUT/registry.json" \
  --pairs 15 \
  --campaign registry-generation-v2-final

python3 Benchmarks/paired_runtime_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --swift-input Sources/HighlightKit/Core/HighlightEngine.swift \
  --output "$OUT/runtime.json" \
  --pairs 15 \
  --campaign registry-generation-v2-final-runtime
```

Run the batches consecutively without starting another build or profile between
them.

## Statistical protocol

- Each campaign uses 15 paired observations after warming every scenario once
  on both executables.
- Scenarios run round-robin inside each pair. Even zero-based pairs run
  baseline then candidate; odd pairs reverse that process order.
- For each pair, `r = candidate / baseline`. The point estimate is
  `exp(mean(log(r)))`. The 95% interval is
  `exp(mean(log(r)) ± t(0.975,14) × SE(log(r)))`, with
  `t(0.975,14) = 2.1447866879169273`.
- Registry and incremental results are latency, where ratios below 1 improve.
  Document results are throughput, where ratios above 1 improve.
- An interval containing 1 is neutral. No completed observation is excluded.
- The runners validate binary hashes, CSV fields, tasks/rounds/operations,
  value units, checksums, and applicable descriptor-build invariants.

The compact CSVs retain all 180 paired observations required to recompute the
results. `pair` is one-based and row order follows actual round-robin execution:

- [registry-samples.csv](registry-samples.csv)
- [runtime-samples.csv](runtime-samples.csv)

## Registry results

All values are latency. `Effect` is the paired candidate/baseline change, not
the ratio of the two unpaired medians.

| Scenario | Baseline median | V2 median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| Warm highlight, 200,000 ops | 1,905.442915 ns/op | 1,907.196040 ns/op | +0.130487% | −1.209353%…+1.488499% | 6/15 | neutral |
| Warm auto-detect, 500 ops × 64 languages | 153,625.668 ns/op | 127,087.750 ns/op | −17.215786% | −17.796075%…−16.631400% | 15/15 | faster |
| Cold contention, 16 tasks × 3 rounds | 4,606,250.000000 ns/round | 2,179,347.333333 ns/round | −52.402955% | −53.865021%…−50.894554% | 15/15 | faster |
| Warm contention, 1 task × 200,000 ops | 1,892.771250 ns/op | 1,882.741250 ns/op | −0.587901% | −1.130900%…−0.041919% | 8/15 | faster |
| Warm contention, 8 tasks × 200,000 ops | 1,407.485625 ns/op | 1,282.609795 ns/op | −4.708523% | −13.138160%…+4.539182% | 14/15 | neutral |
| Warm contention, 32 tasks × 200,000 ops | 1,603.752705 ns/op | 1,535.094375 ns/op | −4.797875% | −8.268663%…−1.195764% | 11/15 | faster |

Cold correctness is exact: the baseline built the descriptor 32–42 times per
three-round observation (604 builds total), while v2 built exactly three times
in every observation (45 total). All warm-highlight and warm-contention
observations built exactly once on both sides.

Registry checksums matched in every pair:

| Scenario | Checksum per side |
|---|---:|
| Warm highlight | 200,000 |
| Auto-warm | 1,000 |
| Cold contention | 48 |
| Warm contention, 1 task | 200,000 |
| Warm contention, 8 tasks | 200,000 |
| Warm contention, 32 tasks | 200,000 |

## Runtime controls

JavaScript, TypeScript, and real-Swift document workloads use 7 timed runs;
SQL uses 25. Incremental JavaScript and Swift use 5 passes, or 10,005 line
highlights per observation. The built-in sample is 62,200 UTF-16 units; the
real-Swift input was 24,941 units.

| Scenario | Baseline median | V2 median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| JavaScript throughput | 1.132186 MU/s | 1.116468 MU/s | **−1.435524%** | **−2.289676%…−0.573905%** | 1/15 | **slower — reject** |
| TypeScript throughput | 0.813220 MU/s | 0.807483 MU/s | **−0.898650%** | **−1.499526%…−0.294109%** | 2/15 | **slower — reject** |
| Real-Swift throughput | 1.843711 MU/s | 1.842744 MU/s | −0.407106% | −1.027889%…+0.217571% | 5/15 | neutral |
| SQL control throughput | 2.027775 MU/s | 2.019663 MU/s | −0.512628% | −1.147891%…+0.126718% | 4/15 | neutral |
| JavaScript incremental latency | 36.081451 µs/line | 36.110799 µs/line | +0.104733% | −0.471355%…+0.684156% | 10/15 | neutral |
| Swift incremental latency | 41.937535 µs/line | 41.998805 µs/line | −0.329281% | −1.727870%…+1.089213% | 7/15 | neutral |

Runtime token checksums matched in all pairs: JavaScript and TypeScript
throughput 5,500; real Swift 868; SQL 4,000; JavaScript incremental 27,500;
Swift incremental 20,500.

## Noise and exclusion policy

Two isolated long observations were retained:

- Warm-contention-8 pair 2: candidate 3,370.082915 ns/op versus baseline
  1,955.320625 ns/op. The candidate won the other 14 pairs, but this retained
  observation widens the formal interval across zero.
- Swift incremental pair 6: baseline 45.634583 µs/line versus candidate
  41.734245 µs/line. It remains in the neutral runtime interval.

Neither point is removed or replaced by a trimmed estimate. The reject-driving
document regressions do not depend on either disturbance: v2 lost 14/15
JavaScript pairs and 13/15 TypeScript pairs.

## Decision

**Rejected.** V2 proves that a publication cache can preserve one-build-per-
generation correctness while improving auto-detection, cold contention, and
32-reader latency. A follow-up must retain those properties without imposing a
resolved cost on JavaScript or TypeScript document highlighting, and must rerun
both campaigns before adoption.
