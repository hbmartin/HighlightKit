# Exact ASCII scan for the bare ECMAScript identifier — ADOPTED

The post-step-28 per-rule profile ranked the bare ECMAScript identifier
`[A-Za-z$_][0-9A-Za-z$_]*` fourth (1.99 ms/run on the JavaScript document),
enumerated by ICU in whole windows — every identifier in the file is a match.
Both character classes are pure ASCII and the pattern has no assertions, so a
raw UTF-16 scan *is* the regex: a non-ASCII unit is simply outside both
classes. The candidate adds an `.asciiIdentifier` prefilter (case-sensitive
rules only — ICU's `.caseInsensitive` folds *input* units, e.g. U+212A KELVIN
SIGN matches `[a-z]`, which a raw ASCII scan cannot see) that synthesizes
group-free matches with no ICU calls on the sequence path. ICU still answers
overlap and pre-scan queries, and remains the ground truth in the
differential suite (adversarial shapes, 1,500-case seeded fuzz, exhaustive
resume positions, surrogate pairs, the Kelvin-sign gate).

Verdict: **ADOPTED**. Both ECMAScript workloads and the JavaScript
incremental latency improved with 95% intervals excluding zero; the
non-ECMAScript controls are neutral, localizing the mechanism to exactly the
grammars that use the rule.

## Controlled inputs

Both arm64 executables are frozen production builds (`swift build -c release`).
The baseline is the adopted step-29 (table-dispatch) binary.

SHA-256 values, verified stable before and after the campaign
(`hashes_stable: true` in [runtime-raw.json](runtime-raw.json)):

- Baseline executable (= step-29 candidate):
  `c86c4528a005218fe49d6553fc93527d1bd5140303358236fb38294a9fcca101`
- Candidate executable:
  `eed85a4e3c0249f536915b5277ac9d66cd10b1c063c4f3bf5b6b0894e135e087`
- Runtime real-Swift input (`Sources/HighlightKit/Core/HighlightEngine.swift`):
  `39b440b784ff36836109ec7b4f36ba9111280eecdb2b33396523a8e40a2e28a6`
- Generated all-space prose input:
  `71883dab6501f6b6a72801e320d568a2ae9e1795c3c5a0708a90bb1c07af11a5`

Machine: MacBook Pro Mac15,11, Apple M3 Max, 36 GB RAM, macOS 26.5.1
(Darwin 25.5.0), arm64; Swift 6.3.2. No build, profiler, or other
CPU-intensive process ran during the campaign.

The campaign ran 2026-07-13 13:15:08–13:16:42 UTC.

## Reproduction

```sh
BASE=/path/to/frozen-step-29/highlight-bench
CANDIDATE=/path/to/frozen-candidate/highlight-bench

python3 Benchmarks/paired_runtime_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --swift-input Sources/HighlightKit/Core/HighlightEngine.swift \
  --output "${TMPDIR:-/tmp}/ascii-identifier-runtime.json" \
  --pairs 15 \
  --campaign ascii-identifier
```

## Statistical protocol

Identical to the [match-groups campaign](../2026-07-13-match-groups/README.md)
(15 interleaved pairs, paired geometric-mean effects, Student-t 95% intervals,
no exclusions, hash/checksum validation). The compact CSV preserves all 105
paired observations: [runtime-samples.csv](runtime-samples.csv).

## Results

| Scenario | Baseline median | Candidate median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| JavaScript throughput | 1.148093 MU/s | 1.181754 MU/s | **+2.833921%** | **+2.527751%…+3.141005%** | 15/15 | **faster** |
| TypeScript throughput | 0.820844 MU/s | 0.837927 MU/s | **+1.988112%** | **+1.715635%…+2.261319%** | 15/15 | **faster** |
| JavaScript incremental latency | 35.697172 µs/line | 35.575154 µs/line | **−0.731479%** | **−1.350070%…−0.109009%** | 9/15 | **faster** |
| Real-Swift throughput | 2.125521 MU/s | 2.123768 MU/s | −0.004664% | −0.182359%…+0.173347% | 8/15 | neutral |
| SQL control throughput | 2.019489 MU/s | 2.018633 MU/s | −0.200829% | −0.707550%…+0.308479% | 7/15 | neutral |
| Swift incremental latency | 41.153165 µs/line | 41.160740 µs/line | −0.078635% | −0.501555%…+0.346083% | 7/15 | neutral |
| All-space JS comment throughput | 18.643914 MU/s | 18.931089 MU/s | +1.221735% | −0.974779%…+3.466971% | 8/15 | neutral |

Only the grammars containing the bare-identifier rule moved; Swift and SQL
are exact controls and are neutral.

Every checksum matched on every observation. `leaks --atExit` reported 0
leaks for the candidate on the JavaScript workload after the campaign.
