# UTF-16 keyword lookup with dense hit counters — ADOPTED

`processKeywords` paid four costs per keyword-pattern word in every grammar:
an `NSString` substring bridge (one heap `String` per word), a Unicode
`String` hash for the `[String: (scope, relevance)]` lookup, `.lowercased()`
for case-insensitive languages, and a second `String`-keyed dictionary for
relevance-saturation hit counts.

This campaign's candidate reworks `CompiledKeywords` into two views of the
same entries: the `String` dictionary remains the source of truth and the
fallback, and a flat UTF-16 open-addressing table (FNV-1a over units, linear
probing, ≥ 2× occupancy, immutable after construction) answers parse-loop
lookups straight from the raw input units. Case-sensitive languages probe
raw units (exact for any input, including non-ASCII keywords);
case-insensitive languages fold ASCII `A-Z` while probing and route any word
containing a non-ASCII unit to the `String` path, where full Unicode folding
applies (U+212A KELVIN SIGN folds to `k` — pinned by a test). Hit counters
moved from a `[String: Int]` dictionary to a dense `[UInt8]` array indexed by
per-language word ids assigned at compile time and shared across modes —
saturation stays per word text per run, exactly highlight.js's counting.
Continuations carry the array (generation-owned since the state-machine
campaign, so indices cannot cross generations).

Verdict: **ADOPTED**. All four throughput workloads improved with 95%
intervals excluding zero; both incremental latencies and the prose control
are neutral.

## Controlled inputs

Both arm64 executables are frozen production builds (`swift build -c release`).
The baseline is the adopted step-30 (ascii-identifier) binary.

SHA-256 values, verified stable before and after the campaign
(`hashes_stable: true` in [runtime-raw.json](runtime-raw.json)):

- Baseline executable (= step-30 candidate):
  `eed85a4e3c0249f536915b5277ac9d66cd10b1c063c4f3bf5b6b0894e135e087`
- Candidate executable:
  `81dad2e01ce73a87e8e169111843c5f2a455022a58e68cfdfb1ba639ee1f97a0`
- Runtime real-Swift input (`Sources/HighlightKit/Core/HighlightEngine.swift`,
  which this step edits — the hash therefore differs from earlier campaigns;
  both sides of this campaign read the identical file):
  `81e34ecbd94d1610e91b6a2a34a0f887810c63e969fa720a0aeddd6834ecde4f`
- Generated all-space prose input:
  `71883dab6501f6b6a72801e320d568a2ae9e1795c3c5a0708a90bb1c07af11a5`

Machine: MacBook Pro Mac15,11, Apple M3 Max, 36 GB RAM, macOS 26.5.1
(Darwin 25.5.0), arm64; Swift 6.3.2. No build, profiler, or other
CPU-intensive process ran during the campaign.

The campaign ran 2026-07-13 13:36:56–13:38:29 UTC.

## Reproduction

```sh
BASE=/path/to/frozen-step-30/highlight-bench
CANDIDATE=/path/to/frozen-candidate/highlight-bench

python3 Benchmarks/paired_runtime_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --swift-input Sources/HighlightKit/Core/HighlightEngine.swift \
  --output "${TMPDIR:-/tmp}/keyword-units-runtime.json" \
  --pairs 15 \
  --campaign keyword-units
```

## Statistical protocol

Identical to the [match-groups campaign](../2026-07-13-match-groups/README.md)
(15 interleaved pairs, paired geometric-mean effects, Student-t 95% intervals,
no exclusions, hash/checksum validation). The compact CSV preserves all 105
paired observations: [runtime-samples.csv](runtime-samples.csv).

## Results

| Scenario | Baseline median | Candidate median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| SQL throughput | 2.020329 MU/s | 2.067604 MU/s | **+2.258396%** | **+1.612053%…+2.908850%** | 14/15 | **faster** |
| Real-Swift throughput | 2.128844 MU/s | 2.147443 MU/s | **+1.142328%** | **+0.569585%…+1.718332%** | 12/15 | **faster** |
| TypeScript throughput | 0.836791 MU/s | 0.845999 MU/s | **+0.999977%** | **+0.545559%…+1.456448%** | 14/15 | **faster** |
| JavaScript throughput | 1.180565 MU/s | 1.194596 MU/s | **+0.928600%** | **+0.564417%…+1.294103%** | 13/15 | **faster** |
| JavaScript incremental latency | 35.736869 µs/line | 35.365488 µs/line | −0.577022% | −1.226397%…+0.076621% | 12/15 | neutral |
| Swift incremental latency | 41.134837 µs/line | 40.852166 µs/line | −0.494134% | −1.138022%…+0.153947% | 13/15 | neutral |
| All-space JS comment throughput | 18.643914 MU/s | 18.654525 MU/s | −0.742770% | −3.623323%…+2.223878% | 7/15 | neutral |

The effect is broad-based (keyword processing runs in every grammar) and
largest for SQL — the most keyword-dense grammar and case-insensitive, so it
previously paid substring + `lowercased()` + two `String` hashes per word.

Every checksum matched on every observation. `leaks --atExit` reported 0
leaks for the candidate on the SQL and real-Swift workloads after the
campaign.
