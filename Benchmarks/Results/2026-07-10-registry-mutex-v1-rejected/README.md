# Registry mutex v1 formal A/B — REJECTED

This directory is the permanent evidence for a rejected intermediate registry
implementation. It is **not the final implementation** and must not be cited as
an adopted optimization. Two independently resolved regressions fail the
project's performance bar:

1. 32-reader warm contention latency regressed **+3.506788%**
   (95% CI **+1.194844%…+5.871552%**).
2. JavaScript document throughput regressed **−2.180742%**
   (95% CI **−3.624356%…−0.715504%**).

Either regression is sufficient to reject v1. The large auto-detection and
cold-contention wins remain useful targets for the next design, but they do not
erase measured hot-path losses.

## Controlled inputs

Both arm64 executables use the same benchmark host, relinked against separate
frozen release object/module sets. They are controlled measurement artifacts,
not substitutes for a normal package release build.

SHA-256 values, stable before and after both campaigns:

- Benchmark host source:
  `540fab4526506bf2f7f0ccce6c964f85c8973b980b94af79be82b63f25a1d6cb`
- Baseline executable:
  `5b3ce1cd5a04952f7b5647f26ac63e517a57962148f778ca38715b436d27a766`
- Rejected mutex-v1 executable:
  `75321d581acd041b04d5387e59186c42b7f8b6fe518395f1cb213988198e7c66`
- Runtime real-Swift input:
  `c625eb052f1f06fe167c5133dff67c76a471ffe796c7970d3c1d920ae56f8e2e`

Machine: MacBook Pro Mac15,11, Apple M3 Max, 36 GB RAM, macOS 26.5.1,
arm64; Swift 6.3.2. No Swift build, profiler, or other CPU-intensive job ran
during either campaign. Registry sampling ran from 2026-07-10
10:07:14–10:08:04 UTC; the runtime controls followed directly at
10:08:10–10:09:48 UTC.

## Reproduction

Freeze two matching production object sets and relink the same benchmark host
against each. Then, from the repository root:

```sh
BASE=/path/to/frozen-baseline/highlight-bench
CANDIDATE=/path/to/frozen-candidate/highlight-bench
OUT="${TMPDIR:-/tmp}/highlight-registry-ab"

python3 Benchmarks/paired_registry_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --output "$OUT/registry.json" \
  --pairs 15 \
  --campaign registry-mutex-v1-rejected

python3 Benchmarks/paired_runtime_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --swift-input Sources/HighlightKit/Core/HighlightEngine.swift \
  --output "$OUT/runtime.json" \
  --pairs 15 \
  --campaign registry-mutex-v1-rejected-runtime
```

The two formal batches must run consecutively without starting another build or
profile between them.

## Statistical protocol

- Every campaign uses 15 paired observations after a full scenario warm-up on
  both executables.
- Scenarios run round-robin inside each pair. Even zero-based pairs run
  baseline then candidate; odd pairs reverse that process order.
- For each pair, `r = candidate / baseline`. The point estimate is
  `exp(mean(log(r)))`. The 95% interval is
  `exp(mean(log(r)) ± t(0.975,14) × SE(log(r)))`, with
  `t(0.975,14) = 2.1447866879169273`.
- Registry results and incremental runtime results are latency: ratios below 1
  are improvements. Document runtime results are throughput: ratios above 1
  are improvements.
- An interval containing 1 is neutral. No completed observation is excluded.
- Binary hashes, scenario fields, task/round/operation counts, output units,
  checksums, and applicable build-count invariants are validated by the runners.

The compact CSV files retain all 180 paired observations required to recompute
the results. Their `pair` columns are one-based and row order follows the actual
round-robin execution order:

- [registry-samples.csv](registry-samples.csv)
- [runtime-samples.csv](runtime-samples.csv)

## Registry results

All values are latency. `Effect` is the paired candidate/baseline change, not
the ratio of unpaired medians.

| Scenario | Baseline median | Mutex-v1 median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| Warm highlight, 200,000 ops | 1,947.650205 ns/op | 1,934.475835 ns/op | −0.520341% | −1.800316%…+0.776318% | 11/15 | neutral |
| Warm auto-detect, 500 ops × 64 languages | 158,228.334 ns/op | 128,532.500 ns/op | −18.045766% | −18.667726%…−17.419050% | 15/15 | faster |
| Cold contention, 16 tasks × 3 rounds | 4,784,416.666667 ns/round | 2,277,069.666667 ns/round | −52.318362% | −53.642259%…−50.956656% | 15/15 | faster |
| Warm contention, 1 task × 200,000 ops | 1,975.084795 ns/op | 1,930.498540 ns/op | −1.169104% | −1.923563%…−0.408841% | 13/15 | faster |
| Warm contention, 8 tasks × 200,000 ops | 1,418.621040 ns/op | 1,251.960000 ns/op | −11.456401% | −13.107506%…−9.773921% | 15/15 | faster |
| Warm contention, 32 tasks × 200,000 ops | 1,634.336875 ns/op | 1,685.899165 ns/op | **+3.506788%** | **+1.194844%…+5.871552%** | 3/15 | **slower — reject** |

The cold correctness result is decisive as well as fast: the baseline compiled
the descriptor 39–42 times per three-round observation (623 builds total),
while mutex v1 compiled exactly three times in every observation (45 total).
All warm-highlight and warm-contention observations built exactly once on both
sides.

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

| Scenario | Baseline median | Mutex-v1 median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| JavaScript throughput | 1.080026 MU/s | 1.058158 MU/s | **−2.180742%** | **−3.624356%…−0.715504%** | 2/15 | **slower — reject** |
| TypeScript throughput | 0.775786 MU/s | 0.772852 MU/s | +0.010425% | −0.663535%…+0.688957% | 9/15 | neutral |
| Real-Swift throughput | 1.755875 MU/s | 1.771648 MU/s | +1.083386% | +0.393302%…+1.778214% | 12/15 | faster |
| SQL control throughput | 1.969054 MU/s | 1.965049 MU/s | −0.911374% | −1.953543%…+0.141872% | 4/15 | neutral |
| JavaScript incremental latency | 37.610141 µs/line | 37.292525 µs/line | −0.181133% | −1.125066%…+0.771812% | 8/15 | neutral |
| Swift incremental latency | 43.284341 µs/line | 43.494149 µs/line | +0.307409% | −0.545428%…+1.167560% | 7/15 | neutral |

Runtime token checksums matched in all pairs: JavaScript and TypeScript
throughput 5,500; real Swift 868; SQL 4,000; JavaScript incremental 27,500;
Swift incremental 20,500.

## Noise and exclusion policy

There was ordinary run-to-run spread but no isolated process stall comparable
to the earlier state-machine campaign. Warm-contention-32 pair ratios ranged
from 0.961086 to 1.119331; JavaScript throughput ratios ranged from 0.932693 to
1.025278. The resolved regressions are not artifacts of deleting a bad point:
mutex v1 lost 12/15 warm-contention-32 pairs and 13/15 JavaScript pairs. Every
observation, including both extremes, remains in the formal statistics and CSV.

## Decision

**Rejected.** The next design must preserve the one-build-per-generation cold
invariant and the auto/cold gains while eliminating both the 32-reader
publication-cache contention cost and the JavaScript hot-path loss.
It must repeat both formal campaigns before adoption.
