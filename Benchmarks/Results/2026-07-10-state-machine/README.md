# State-machine and continuation runtime A/B — 2026-07-10

This campaign compares the frozen built-in-theme-cache baseline with the
state-machine, continuation-lifetime, sublanguage-recursion, and saturated
keyword-hit candidate. Both executables were production binaries from
`swift build -c release`; no `swift test`/`-enable-testing` product was used.

## Reproduction

Freeze both production executables before starting, then run from the repository
root while no other CPU-intensive build or profile is active:

```sh
BASE=/path/to/frozen-baseline/highlight-bench
CANDIDATE=/path/to/frozen-candidate/highlight-bench
OUTPUT="${TMPDIR:-/tmp}/highlight-state-machine-ab/raw.json"

python3 Benchmarks/paired_runtime_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --swift-input Sources/HighlightKit/Core/HighlightEngine.swift \
  --output "$OUTPUT" \
  --pairs 15 \
  --campaign 2026-07-10-state-machine
```

The runner refuses sample counts other than 15 because its checked 95% Student-t
critical value, `2.1447866879169273`, is specific to 14 degrees of freedom.
Supporting another pair count requires adding and reviewing the corresponding
critical value rather than silently reusing this one.

## Method

- Machine: MacBook Pro Mac15,11, Apple M3 Max, 36 GB RAM, macOS 26.5.1,
  arm64; Swift 6.3.2. Campaign interval: 2026-07-10 09:14:18–09:15:59 UTC.
- Six scenarios run round-robin inside each of 15 pairs. Even zero-based pairs
  run baseline then candidate; odd pairs reverse the order.
- Before sampling, every scenario runs once per executable. The binary-first
  warm-up order alternates by scenario. Each process also performs the
  benchmark host's grammar warm-up before its internally timed loop.
- Full-document JavaScript, TypeScript, and real-Swift throughput use 7 inner
  runs. SQL uses 25 as a control. JavaScript and Swift incremental workloads use
  5 passes, or 10,005 line-highlight calls per observation.
- The built-in JavaScript sample is 62,200 UTF-16 units; the real-Swift input in
  this campaign is 24,832 UTF-16 units.
- The real-Swift workload is the same working-tree
  `Sources/HighlightKit/Core/HighlightEngine.swift` file for both executables.
  The runner hashes it before and after the campaign and invalidates the batch
  if it changes.
- For each pair, `r = candidate / baseline`. The reported point estimate is
  `exp(mean(log(r)))`. The 95% interval is
  `exp(mean(log(r)) ± t(0.975,14) × SE(log(r)))`.
- Throughput ratios above 1 are improvements; latency ratios below 1 are
  improvements. An interval that includes 1 is reported as neutral.
- No completed observation is excluded. This rule was selected before looking
  at the samples.
- Token checksums and observable workload shape must match within every pair.
  All 90 pairs passed. Binary and input hashes were identical before and after.

The host prints internally timed seconds to three decimal places but rounds its
headline MU/s or µs/line field to two decimals. The analysis therefore derives
`value` from the internal seconds and exact unit/call count, and retains both
the source seconds and normalized value in [samples.csv](samples.csv). The CI
does not model output quantization; in particular, the short real-Swift runs are
reported as neutral even though their lower bound is very close to zero change.

## Results

`Change` and its CI are the paired geometric-mean candidate/baseline effect, not
the ratio of the two unpaired medians.

| Scenario | Baseline median | Candidate median | Ratio B/A | Change | 95% change CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---:|---|
| JavaScript throughput | 1.056796 MU/s | 1.054237 MU/s | 1.004345045 | +0.434505% | −0.726560%…+1.609148% | 9/15 | neutral |
| TypeScript throughput | 0.762522 MU/s | 0.776114 MU/s | 1.007184702 | +0.718470% | −0.138330%…+1.582622% | 10/15 | neutral |
| Real-Swift throughput | 1.738240 MU/s | 1.738240 MU/s | 1.010736313 | +1.073631% | −0.005230%…+2.164133% | 9/15 | neutral |
| SQL control throughput | 1.948622 MU/s | 1.968354 MU/s | 1.028018725 | +2.801872% | −1.408549%…+7.192103% | 14/15 | neutral |
| JavaScript incremental latency | 37.981009 µs/line | 37.681159 µs/line | 0.957426884 | −4.257312% | −11.046605%…+3.050169% | 12/15 | neutral |
| Swift incremental latency | 44.477761 µs/line | 43.878061 µs/line | 0.991196144 | −0.880386% | −1.516251%…−0.240415% | 12/15 | faster |

The candidate has no statistically resolved throughput or JavaScript
incremental regression in this batch. Swift incremental latency improves by
0.88% with an interval entirely below zero. The correctness/lifetime changes
therefore remain acceptable on the measured runtime paths.

## Noise and outlier policy

Two baseline processes suffered isolated long-duration disturbances:

- SQL pair 3: baseline 1.217 s, candidate 0.902 s.
- JavaScript incremental pair 11: baseline 0.649 s, candidate 0.385 s.

They were retained exactly as required by the preselected no-exclusion rule.
Their impact appears as wider SQL and JavaScript-incremental t intervals; no
post-hoc trimmed or outlier-excluded result is substituted for the formal one.

## Integrity

SHA-256 values, stable across the campaign:

- Baseline executable:
  `3e1dc65a8fcf5757c6740cb4f2606f724d4d07860b8192d30707800cfe37a5e4`
- Candidate executable:
  `84bd81e0c4a63a06c32c87b49b024cb255689f7fb2ccd634a7d18f30da611523`
- Real-Swift input:
  `e5a8d25ec4cc0b93f7118e5416263f8d48238b96854a0a27d0926b524b84294d`

Per-observation token checksums were constant and identical across both sides:

| Scenario | Token checksum |
|---|---:|
| JavaScript throughput | 5,500 |
| TypeScript throughput | 5,500 |
| Real-Swift throughput | 868 |
| SQL control throughput | 4,000 |
| JavaScript incremental | 27,500 |
| Swift incremental | 20,500 |

The original verbose JSON is intentionally not checked in: it duplicated full
commands, stdout, display metrics, and parsed fields for every side. The compact
CSV preserves all 90 paired observations needed to recompute the formal
statistics: scenario/kind, pair index, process order, both seconds, both
normalized values, and both checksums.

The CSV's `pair` column is one-based, and its row order follows the original
round-robin execution order.
