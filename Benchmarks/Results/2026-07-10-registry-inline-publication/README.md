# Registry inline publication v3 — ADOPTED

V3 keeps one serialized compilation per registration generation, but stores the
successfully compiled graph beside its canonical registry entry. A warm
canonical lookup therefore performs one `Dictionary` lookup under the global
`Synchronization.Mutex`; v2 performed a second hash through an
`ObjectIdentifier` publication table.

The formal result meets both adoption conditions:

1. Registry work improves materially: warm auto-detection is **18.838459%**
   faster, cold contention is **53.282884%** faster, and 8-reader contention is
   **4.956856%** faster, all with 95% intervals excluding zero.
2. JavaScript, TypeScript, real-Swift, SQL, and both incremental controls have
   no resolved regression. A second complete 15-pair runtime campaign reached
   the same conclusion; the pooled 30-pair intervals also all cross zero.

Verdict: **ADOPTED**. This supersedes the rejected mutex-v1 and publication-v2
implementations, whose raw evidence remains checked in separately.

## Controlled inputs

Both arm64 executables use the same benchmark host, relinked against separate
frozen production (`swift build -c release`) object/module sets.

SHA-256 values, stable before and after every campaign:

- Benchmark host source:
  `540fab4526506bf2f7f0ccce6c964f85c8973b980b94af79be82b63f25a1d6cb`
- Baseline executable:
  `5b3ce1cd5a04952f7b5647f26ac63e517a57962148f778ca38715b436d27a766`
- Adopted v3 executable:
  `7154e69d972c4db7513cd69cc60429d5d39dcdde20a78eb12a6c28bb3e9980a1`
- V3 `LanguageRegistry.swift` source:
  `b8aa27c7c39a60123afa4e911375fb40f7c9a5d7d2fdeb22fdbe43b7865ee15e`
- Runtime real-Swift input:
  `c625eb052f1f06fe167c5133dff67c76a471ffe796c7970d3c1d920ae56f8e2e`

Machine: MacBook Pro Mac15,11, Apple M3 Max, 36 GB RAM, macOS 26.5.1,
arm64; Swift 6.3.2. `pmset` reported no thermal or performance warning. No
build, profiler, or other CPU-intensive process ran during a campaign.

The primary Registry campaign ran from 2026-07-10 10:51:46–10:52:35 UTC;
the primary runtime campaign followed immediately from 10:52:35–10:54:09.
The independent runtime confirmation ran from 10:55:00–10:56:38.

## Reproduction

```sh
BASE=/path/to/frozen-baseline/highlight-bench
CANDIDATE=/path/to/frozen-v3-candidate/highlight-bench
OUT="${TMPDIR:-/tmp}/highlight-registry-v3-ab"

python3 Benchmarks/paired_registry_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --output "$OUT/registry.json" \
  --pairs 15 \
  --campaign registry-inline-publication-v3

python3 Benchmarks/paired_runtime_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --swift-input Sources/HighlightKit/Core/HighlightEngine.swift \
  --output "$OUT/runtime.json" \
  --pairs 15 \
  --campaign registry-inline-publication-v3-runtime
```

The confirmation repeats the second command with a fresh output path and
campaign label. It is additional evidence, not a replacement sample set.

## Statistical protocol

- Each campaign warms every scenario on both executables, then retains 15
  paired observations. Scenarios run round-robin; even zero-based pairs run
  baseline then candidate and odd pairs reverse the process order.
- For each pair, `r = candidate / baseline`. The point estimate is
  `exp(mean(log(r)))`. Fifteen-pair intervals use Student-t in the log domain,
  `t(0.975,14) = 2.1447866879169273`, then exponentiate.
- Registry and incremental values are latency (lower is better); document
  values are throughput (higher is better). An interval containing 1 is
  neutral.
- No completed observation is excluded. Runners validate executable/input
  hashes, scenario shape, checksums, operation counts, and descriptor build
  counts before accepting a campaign.

The compact CSVs preserve all 270 paired scenario observations:

- [registry-samples.csv](registry-samples.csv)
- [runtime-samples.csv](runtime-samples.csv)
- [runtime-confirm-samples.csv](runtime-confirm-samples.csv)

## Registry results

All values are latency. `Effect` is the paired candidate/baseline change, not
the ratio of unpaired medians.

| Scenario | Baseline median | V3 median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| Warm highlight, 200,000 ops | 1,919.240835 ns/op | 1,913.933750 ns/op | −0.003646% | −1.530507%…+1.546891% | 6/15 | neutral |
| Warm auto-detect, 500 ops × 64 languages | 157,104.668 ns/op | 126,248.750 ns/op | **−18.838459%** | **−19.620823%…−18.048481%** | 15/15 | **faster** |
| Cold contention, 16 tasks × 3 rounds | 4,679,180.333333 ns/round | 2,189,083.333333 ns/round | **−53.282884%** | **−54.546825%…−51.983797%** | 15/15 | **faster** |
| Warm contention, 1 task × 200,000 ops | 1,933.207920 ns/op | 1,950.638955 ns/op | +0.111755% | −0.687944%…+0.917893% | 7/15 | neutral |
| Warm contention, 8 tasks × 200,000 ops | 1,404.199790 ns/op | 1,343.005835 ns/op | **−4.956856%** | **−6.904654%…−2.968306%** | 14/15 | **faster** |
| Warm contention, 32 tasks × 200,000 ops | 1,602.464790 ns/op | 1,573.215210 ns/op | −2.912364% | −6.036749%…+0.315910% | 11/15 | neutral |

The correctness result is exact: baseline cold contention built 39–42 times
per three-round observation (619 total); v3 built exactly three times every
time (45 total). Every warm observation built exactly once on both sides. All
checksums matched.

## Primary runtime controls

JavaScript, TypeScript, and real-Swift document workloads use 7 timed runs;
SQL uses 25. Incremental workloads use 5 passes (10,005 line highlights).

| Scenario | Baseline median | V3 median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| JavaScript throughput | 1.121573 MU/s | 1.124624 MU/s | +0.321450% | −0.916237%…+1.574597% | 5/15 | neutral |
| TypeScript throughput | 0.799543 MU/s | 0.805031 MU/s | +0.310060% | −0.628328%…+1.257310% | 9/15 | neutral |
| Real-Swift throughput | 1.850612 MU/s | 1.843243 MU/s | −5.303857% | −14.141034%…+4.442902% | 3/15 | neutral |
| SQL control throughput | 2.006017 MU/s | 2.012247 MU/s | +0.017920% | −0.651186%…+0.691532% | 8/15 | neutral |
| JavaScript incremental latency | 36.025729 µs/line | 36.039676 µs/line | +0.271447% | −0.569504%…+1.119510% | 7/15 | neutral |
| Swift incremental latency | 42.113418 µs/line | 41.955072 µs/line | +0.012872% | −1.196973%…+1.237530% | 8/15 | neutral |

Every checksum matched: JavaScript/TypeScript 5,500; real Swift 868; SQL
4,000; JavaScript incremental 27,500; Swift incremental 20,500.

## Independent runtime confirmation

The second complete batch also classified all six scenarios as neutral:

| Scenario | Effect | 95% effect CI |
|---|---:|---:|
| JavaScript throughput | +0.150242% | −1.604668%…+1.936451% |
| TypeScript throughput | −0.931477% | −2.353130%…+0.510874% |
| Real-Swift throughput | +4.464737% | −4.728477%…+14.545048% |
| SQL control throughput | +0.906487% | −1.178048%…+3.034994% |
| JavaScript incremental latency | +2.102345% | −1.082447%…+5.389677% |
| Swift incremental latency | −2.267786% | −5.412181%…+0.981138% |

For an additional descriptive check, pooling the two predeclared sample sets
and using `t(0.975,29) = 2.045229642132703` gives neutral 30-pair intervals:
JavaScript +0.235809% (−0.774000%…+1.255895%), TypeScript −0.312641%
(−1.148151%…+0.529930%), real Swift −0.539416%
(−6.864097%…+6.214761%), SQL +0.461221% (−0.579077%…+1.512405%),
JavaScript incremental +1.182755% (−0.397516%…+2.788098%), and Swift
incremental −1.134033% (−2.793201%…+0.553454%).

## Noise and exclusion policy

All stalls remain in the data. The primary real-Swift pair 6 candidate ran at
0.891456 MU/s versus a 1.780216 baseline (roughly 2× slower). The confirmation
had the opposite disturbance in pair 5: baseline 0.682850 versus candidate
1.294874 MU/s. The confirmation also contains visible stalls on both sides in
SQL and incremental scenarios. None is trimmed, winsorized, rerun in place, or
silently replaced; this is why those intervals are wide. The repeat campaign
and pooled view are reported alongside, not instead of, the primary result.

## Decision

**Adopted.** Inline publication preserves the generation/lifecycle invariants
and the exact one-build cold result, produces large resolved auto/cold gains
and a resolved 8-reader gain, and removes the v1/v2 resolved runtime losses.
Warm 1-reader, warm 32-reader, and every document/incremental control are
statistically neutral; no negative interval excludes zero.
