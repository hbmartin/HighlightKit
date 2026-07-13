# Direct-index literal-table dispatch — ADOPTED

The two literal-table prefilters probed a `Dictionary<UInt16, [[UInt16]]>` at
every input position: `extendValueStarters` hashes the current unit on every
character of the document, and `extendPunctuatedKeywords` on every candidate
position. A `sample` profile of the step-28 binary showed
`__RawDictionaryStorage.find` + `Hasher._hash` among the hottest non-ICU
frames on both the JavaScript and real-Swift workloads.

This campaign's candidate replaces the dictionary with a 128-slot
directly-indexed bucket array in both `OperatorTable` and `KeywordTable`:
dispatch is one bounds-checked array load (`u < 128` then `byFirstUnit[Int(u)]`,
empty bucket = miss). Construction fails closed on any non-ASCII first unit —
the rule then keeps plain ICU enumeration, so semantics cannot drift.
(`KeywordTable.parse` already guaranteed ASCII word first units; the width
guard makes the array bound structural in both tables.) Per-bucket alternation
order is unchanged, preserving ICU's first-listed-alternative semantics.

Verdict: **ADOPTED**. Both workloads that exercise the tables improved with
95% intervals excluding zero and 15/15 pairs; every control is neutral.

## Controlled inputs

Both arm64 executables are frozen production builds (`swift build -c release`).
The baseline is the adopted step-28 (match-groups) binary.

SHA-256 values, verified stable before and after the campaign
(`hashes_stable: true` in [runtime-raw.json](runtime-raw.json)):

- Baseline executable (= step-28 candidate):
  `9834e6069268fdee7b42f93bc9801376dc99c8a88eca34de884d0675f6ded85e`
- Candidate executable:
  `c86c4528a005218fe49d6553fc93527d1bd5140303358236fb38294a9fcca101`
- Runtime real-Swift input (`Sources/HighlightKit/Core/HighlightEngine.swift`):
  `39b440b784ff36836109ec7b4f36ba9111280eecdb2b33396523a8e40a2e28a6`
- Generated all-space prose input:
  `71883dab6501f6b6a72801e320d568a2ae9e1795c3c5a0708a90bb1c07af11a5`

Machine: MacBook Pro Mac15,11, Apple M3 Max, 36 GB RAM, macOS 26.5.1
(Darwin 25.5.0), arm64; Swift 6.3.2. No build, profiler, or other
CPU-intensive process ran during the campaign.

The campaign ran 2026-07-13 12:58:34–13:00:10 UTC.

## Reproduction

```sh
BASE=/path/to/frozen-step-28/highlight-bench
CANDIDATE=/path/to/frozen-candidate/highlight-bench

python3 Benchmarks/paired_runtime_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --swift-input Sources/HighlightKit/Core/HighlightEngine.swift \
  --output "${TMPDIR:-/tmp}/table-dispatch-runtime.json" \
  --pairs 15 \
  --campaign table-dispatch
```

## Statistical protocol

Identical to the [match-groups campaign](../2026-07-13-match-groups/README.md)
(15 interleaved pairs, paired geometric-mean effects, Student-t 95% intervals,
no exclusions, hash/checksum validation). The compact CSV preserves all 105
paired observations: [runtime-samples.csv](runtime-samples.csv).

## Results

| Scenario | Baseline median | Candidate median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| Real-Swift throughput | 1.998466 MU/s | 2.114211 MU/s | **+6.132487%** | **+5.825841%…+6.440022%** | 15/15 | **faster** |
| JavaScript throughput | 1.123135 MU/s | 1.145095 MU/s | **+1.480523%** | **+1.057850%…+1.904964%** | 15/15 | **faster** |
| TypeScript throughput | 0.814090 MU/s | 0.818819 MU/s | −0.001693% | −1.838750%…+1.869743% | 11/15 | neutral |
| SQL control throughput | 2.014745 MU/s | 2.011346 MU/s | +0.196874% | −0.246758%…+0.642479% | 9/15 | neutral |
| JavaScript incremental latency | 36.143637 µs/line | 36.076000 µs/line | −3.101554% | −8.984549%…+3.161703% | 8/15 | neutral |
| Swift incremental latency | 41.621622 µs/line | 41.632167 µs/line | −0.340019% | −1.008107%…+0.332578% | 9/15 | neutral |
| All-space JS comment throughput | 18.515757 MU/s | 18.568204 MU/s | −0.011188% | −2.181305%…+2.207073% | 7/15 | neutral |

The effect concentrates exactly where the tables are probed per position:
the Swift grammar's punctuated-keyword scan (+6.13%) and the ECMAScript
value-starter scan (+1.48% on the JavaScript document). The SQL grammar has
no literal-table rule and is neutral, as expected.

Every checksum matched on every observation. `leaks --atExit` reported 0
leaks for the candidate on a real-Swift source workload after the campaign.
