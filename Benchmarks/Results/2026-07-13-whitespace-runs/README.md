# Whitespace-run synthesis for bare `\s+` rules — ADOPTED

Grammars carry bare `\s+` rules (for example the JavaScript function-params
mode), previously matched by whole-window ICU enumeration. On units below
0x80, ICU's `\s` is exactly TAB–CR (0x09–0x0D) plus space (0x20), so the
candidate adds a `.whitespaceRun` prefilter that synthesizes ASCII runs
directly (zero capture groups → `.none`). `\s` is Unicode-aware — U+0085,
U+00A0, U+1680, U+2000–U+200A, U+2028/29, U+202F, U+205F, U+3000 — so any
≥ 0x80 unit seen while searching (it could itself be whitespace) or ending a
run (it could extend `\s+`) defers the window to ICU enumeration. The
differential suite pins the sequence to raw ICU on adversarial shapes
(NBSP, NEL, line/paragraph separators, ogham, ideographic space, zero-width
space, huge runs), a 1,500-case seeded fuzz corpus, and exhaustive resume
positions.

Verdict: **ADOPTED**. The effect lands on the editor path: JavaScript
incremental latency improved in 15/15 pairs with a tight interval — per-line
scans cannot amortize the per-window enumeration cost the way whole-document
runs do. TypeScript throughput is marginally faster (interval excludes zero);
every other scenario is neutral and nothing regressed.

## Controlled inputs

Both arm64 executables are frozen production builds (`swift build -c release`).
The baseline is the adopted step-31 (keyword-units) binary — step 32 was
rejected and reverted, so step 31 is the shipped predecessor.

SHA-256 values, verified stable before and after the campaign
(`hashes_stable: true` in [runtime-raw.json](runtime-raw.json)):

- Baseline executable (= step-31 candidate):
  `81dad2e01ce73a87e8e169111843c5f2a455022a58e68cfdfb1ba639ee1f97a0`
- Candidate executable:
  `05299888b90a3a8280d35c9e908c696f70d102756cce0d849f214c02d74f68bb`
- Runtime real-Swift input (`Sources/HighlightKit/Core/HighlightEngine.swift`):
  `81e34ecbd94d1610e91b6a2a34a0f887810c63e969fa720a0aeddd6834ecde4f`
- Generated all-space prose input:
  `71883dab6501f6b6a72801e320d568a2ae9e1795c3c5a0708a90bb1c07af11a5`

Machine: MacBook Pro Mac15,11, Apple M3 Max, 36 GB RAM, macOS 26.5.1
(Darwin 25.5.0), arm64; Swift 6.3.2. `ps` verified no process above 30% CPU
before launch (the step-32 disturbance lesson).

The campaign ran 2026-07-13 14:19:06–14:20:39 UTC.

## Reproduction

```sh
BASE=/path/to/frozen-step-31/highlight-bench
CANDIDATE=/path/to/frozen-candidate/highlight-bench

python3 Benchmarks/paired_runtime_ab.py \
  --baseline "$BASE" \
  --candidate "$CANDIDATE" \
  --swift-input Sources/HighlightKit/Core/HighlightEngine.swift \
  --output "${TMPDIR:-/tmp}/whitespace-runs-runtime.json" \
  --pairs 15 \
  --campaign whitespace-runs
```

## Statistical protocol

Identical to the [match-groups campaign](../2026-07-13-match-groups/README.md)
(15 interleaved pairs, paired geometric-mean effects, Student-t 95% intervals,
no exclusions, hash/checksum validation). The compact CSV preserves all 105
paired observations: [runtime-samples.csv](runtime-samples.csv).

## Results

| Scenario | Baseline median | Candidate median | Effect | 95% effect CI | Better pairs | Verdict |
|---|---:|---:|---:|---:|---:|---|
| JavaScript incremental latency | 35.321731 µs/line | 34.848155 µs/line | **−1.368569%** | **−1.677463%…−1.058704%** | 15/15 | **faster** |
| TypeScript throughput | 0.842357 MU/s | 0.842635 MU/s | **+0.240057%** | **+0.010660%…+0.469980%** | 11/15 | **faster** (marginal) |
| JavaScript throughput | 1.190181 MU/s | 1.195902 MU/s | +0.196927% | −0.209793%…+0.605304% | 9/15 | neutral |
| Real-Swift throughput | 2.143306 MU/s | 2.140723 MU/s | +0.097148% | −0.173828%…+0.368859% | 5/15 | neutral |
| SQL control throughput | 2.055063 MU/s | 2.055846 MU/s | +0.122696% | −0.366128%…+0.613918% | 10/15 | neutral |
| Swift incremental latency | 40.979602 µs/line | 40.998830 µs/line | +0.018880% | −0.405444%…+0.445012% | 7/15 | neutral |
| All-space JS comment throughput | 18.952983 MU/s | 18.334501 MU/s | −2.327522% | −5.190108%…+0.621494% | 4/15 | neutral |

Every checksum matched on every observation. `leaks --atExit` reported 0
leaks for the candidate on the JavaScript workload after the campaign.
