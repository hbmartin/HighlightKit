# Repository-aware highlighting runtime — ADOPTED

This campaign checks the complete repository-aware, cancellable, budgeted
highlighting change against the restored green baseline. The feature work adds
new public layers around parsing and six registered grammars; this comparison
specifically verifies that existing named-language parser throughput and
incremental continuation latency did not regress.

Verdict: **ADOPTED**. Six of seven scenarios are neutral. The SQL control is
0.84% faster (95% CI +0.17%…+1.51%); no scenario has a resolved regression.

## Controlled inputs

Both arm64 executables are frozen production builds from
`swift build -c release -j 1` using Apple Swift 6.2.4 / Xcode 26.3.

- Baseline source: `3d97faefd73f9c618140c0c00f3648642ffa32fb`
  (the prerequisite Swift-grammar compilation fix)
- Candidate source: `62b85575fbda6653e3ff81da4fd74b785f0eb2fa`, plus
  the benchmark/documentation changes in the following commit
- Baseline executable SHA-256:
  `6cd40ef080506fe0fba55a3088cf4a5a12cfe1dc9b88120ccb917c731805735e`
- Candidate executable SHA-256:
  `6e41e568af3503585ccc69b18cab0487f714f6c785c57d28421147a445bd23c1`
- Shared real-Swift input SHA-256:
  `e4d4df5d1b16dd76613cf663bf12d38407d03ffc6793d49036138b21bfb9bb6d`
- Generated all-space prose input SHA-256:
  `71883dab6501f6b6a72801e320d568a2ae9e1795c3c5a0708a90bb1c07af11a5`

The hashes were identical before and after the campaign. The machine was a
MacBook Pro `Mac16,7`, Apple M4 Pro (14 cores), 48 GB RAM, macOS 15.7.7
(Darwin 24.6.0), arm64. The campaign ran 2026-07-23 15:17:40–15:19:01 UTC.

## Reproduction

```sh
BASELINE=/path/to/3d97fae/highlight-bench
CANDIDATE=.build/release/highlight-bench

python3 Benchmarks/paired_runtime_ab.py \
  --baseline "$BASELINE" \
  --candidate "$CANDIDATE" \
  --swift-input Sources/HighlightKit/Languages/Swift.swift \
  --output "${TMPDIR:-/tmp}/repository-aware-runtime.json" \
  --campaign repository-aware-highlighting \
  --pairs 15 \
  --prose-spaces 8192
```

## Statistical protocol

Every scenario was warmed once per executable. Fifteen process-level pairs
then alternated baseline-first and candidate-first order. Effects are paired
geometric-mean candidate/baseline ratios with Student-t 95% intervals in the
log domain. Intervals crossing zero are neutral. There were no exclusions;
all 105 completed paired observations and their commands, stdout, timings,
checksums, hashes, and summaries are retained in
[`runtime-raw.json`](runtime-raw.json). The generated prose fixture is retained
as [`runtime-raw.prose-8192.js`](runtime-raw.prose-8192.js).

## Results

| Scenario | Baseline median | Candidate median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| JavaScript throughput | 1.371510 MU/s | 1.375632 MU/s | +1.437098% | −0.626537%…+3.543587% | 9/15 | neutral |
| TypeScript throughput | 1.016203 MU/s | 1.015870 MU/s | +0.261355% | −0.279105%…+0.804744% | 11/15 | neutral |
| Real-Swift throughput | 1.927331 MU/s | 1.925577 MU/s | +0.149437% | −0.476185%…+0.778991% | 9/15 | neutral |
| SQL control throughput | 2.377304 MU/s | 2.398027 MU/s | **+0.840840%** | **+0.174374%…+1.511740%** | 13/15 | **faster** |
| JavaScript incremental latency | 34.598817 µs/line | 34.773938 µs/line | +0.145481% | −0.989405%…+1.293376% | 6/15 | neutral |
| Swift incremental latency | 40.286861 µs/line | 40.504273 µs/line | +0.555254% | −1.068296%…+2.205448% | 5/15 | neutral |
| All-space JS comment throughput | 21.563158 MU/s | 22.088754 MU/s | +4.885542% | −0.580125%…+10.651687% | 13/15 | neutral |

Every baseline/candidate checksum matched in every observation. The results
support the intended architecture: repository resolution, caching, rendering,
and document state are opt-in consumer layers and do not impose a resolved
cost on the existing named-language parser path.
