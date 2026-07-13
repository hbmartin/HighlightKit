# Inline match-group representation — ADOPTED

The per-run rule match cache stored one `NSTextCheckingResult` per cached
match. The four hand-written prefilter paths (`(\s*)\(` params lead-in, Swift
punctuated keywords, value-starter operators, Swift identifier shapes) each
allocated one via `regularExpressionCheckingResult(ranges:count:…)` — plus a
heap `[NSRange]` buffer for the two multi-group shapes — for every real match,
only so the parse loop could later ask for capture groups it rarely needs.

This campaign's candidate replaces the stored object with an inline enum,
`MatchGroups`: `.none` (no groups beyond the full match), `.group1(length:)`
(group 1 = the leading `length` units; both synthesized group shapes have this
form), and `.icu(NSTextCheckingResult)` for real ICU matches. Group ranges are
resolved on demand by one shared accessor with JavaScript `match[N]` semantics.
Two secondary effects: consulting a rule's next cached match now reads the
parallel `starts`/`ends` arrays instead of dispatching `NSTextCheckingResult
.range` per consultation, and storing an ICU match reads `.range` once instead
of three times.

Verdict: **ADOPTED**. Every affected scenario moved in the expected direction
with 95% intervals excluding zero; no scenario regressed.

## Controlled inputs

Both arm64 executables are frozen production builds (`swift build -c release`).

SHA-256 values, verified stable before and after the campaign
(`hashes_stable: true` in [runtime-raw.json](runtime-raw.json)):

- Baseline executable:
  `3bf8a2e05a1a820b680e670cd22ca84b6ae100699ee5f1ca8fd13ec6ee12027f`
- Candidate executable:
  `9834e6069268fdee7b42f93bc9801376dc99c8a88eca34de884d0675f6ded85e`
- Runtime real-Swift input (`Sources/HighlightKit/Core/HighlightEngine.swift`):
  `39b440b784ff36836109ec7b4f36ba9111280eecdb2b33396523a8e40a2e28a6`
- Generated all-space prose input:
  `71883dab6501f6b6a72801e320d568a2ae9e1795c3c5a0708a90bb1c07af11a5`

Machine: MacBook Pro Mac15,11, Apple M3 Max, 36 GB RAM, macOS 26.5.1
(Darwin 25.5.0), arm64; Swift 6.3.2. No build, profiler, or other
CPU-intensive process ran during the campaign.

The campaign ran 2026-07-13 12:21:36–12:23:14 UTC.

## Reproduction

```sh
BASE=/path/to/frozen-baseline/highlight-bench
CANDIDATE=/path/to/frozen-candidate/highlight-bench

python3 Benchmarks/paired_runtime_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --swift-input Sources/HighlightKit/Core/HighlightEngine.swift \
  --output "${TMPDIR:-/tmp}/match-groups-runtime.json" \
  --pairs 15 \
  --campaign match-groups
```

## Statistical protocol

Identical to the [state-machine campaign](../2026-07-10-state-machine/README.md):
15 interleaved process-level pairs per scenario with alternating order after a
full warm-up of both executables; paired geometric-mean effects with Student-t
95% intervals in the log domain (`t(0.975,14) = 2.1447866879169273`); no
completed observation excluded. The runner validates executable/input hashes,
scenario shape, and checksums before accepting a campaign.

The compact CSV preserves all 105 paired scenario observations:
[runtime-samples.csv](runtime-samples.csv).

## Results

Throughput scenarios report MU/s (higher is better); incremental scenarios
report µs/line (lower is better). `Effect` is the paired candidate/baseline
change, not the ratio of unpaired medians.

| Scenario | Baseline median | Candidate median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| JavaScript throughput | 1.070912 MU/s | 1.122490 MU/s | **+4.781175%** | **+4.533866%…+5.029068%** | 15/15 | **faster** |
| TypeScript throughput | 0.777755 MU/s | 0.808091 MU/s | **+3.775524%** | **+3.577960%…+3.973464%** | 15/15 | **faster** |
| Real-Swift throughput | 1.932066 MU/s | 1.973916 MU/s | **+1.815625%** | **+1.083954%…+2.552593%** | 14/15 | **faster** |
| SQL control throughput | 1.985053 MU/s | 2.005108 MU/s | **+0.865841%** | **+0.444986%…+1.288460%** | 13/15 | **faster** |
| JavaScript incremental latency | 36.948105 µs/line | 36.356951 µs/line | **−1.583964%** | **−1.918595%…−1.248192%** | 15/15 | **faster** |
| Swift incremental latency | 42.033383 µs/line | 41.916184 µs/line | −0.228694% | −0.714212%…+0.259199% | 10/15 | neutral |
| All-space JS comment throughput | 17.716757 MU/s | 18.631535 MU/s | +2.442851% | −1.153149%…+6.169672% | 10/15 | neutral |

The SQL control was expected to be near-neutral and instead improved with an
interval excluding zero — consistent with the two mechanism-level effects that
apply to every grammar (no `.range` dispatch per rule consultation; one
`.range` read instead of three per stored ICU match), not with noise.

Every checksum matched on every observation: JavaScript/TypeScript 5,500;
real Swift 1,154; SQL 4,000; JavaScript incremental 27,500; Swift incremental
20,500; prose control 1.

`leaks --atExit` reported 0 leaks for the candidate on both the JavaScript
sample and a real-Swift source workload after the campaign.
