# Line-end synthesis for bare `$` rules — REJECTED & REVERTED

Post-step-33 per-rule profiles showed the bare `$` rule costing ~0.9–1.1 ms
per run on both the JavaScript and Swift documents (line comments in nearly
every grammar end at `$`). A `.lineEnd` prefilter synthesized its zero-width
matches — before every `\r`, before every `\n` not preceded by `\r`, and at
end of input, matching an ICU semantics probe under the engine's exact
options (`\r\n` is one boundary matched before the `\r`; a trailing newline
matches both before it and at EOF; NEL/U+2028/U+2029 defer to ICU). A
differential suite (adversarial shapes, 1,500-case fuzz, exhaustive resume
positions, non-multiline gate) passed throughout, as did all 375 fixtures.

Two variants were measured; **both regress JavaScript with intervals
excluding zero** while improving real Swift, so the change fails the
no-resolved-regression gate and was reverted.

## Variant 1 — one append per window call

[runtime-raw-one-per-call.json](runtime-raw-one-per-call.json) /
[runtime-samples-one-per-call.csv](runtime-samples-one-per-call.csv),
2026-07-13 14:54:07–14:55:39 UTC, hashes stable.

| Scenario | Effect | 95% CI | Better pairs | Verdict |
|---|---:|---:|---:|---|
| JavaScript throughput | **−0.820812%** | −1.444592%…−0.193084% | 3/15 | **slower** |
| Real-Swift throughput | **+2.774311%** | +2.399924%…+3.150067% | 15/15 | faster |
| All-space JS comment | **+34.951603%** | +31.470419%…+38.524965% | 15/15 | faster |
| TS / SQL / both incrementals | — | all cross zero | — | neutral |

## Variant 2 — appends batched to the window size

Hypothesis: variant 1's regression was per-call dispatch on line-dense input
(one `extendWindow` round-trip per line versus ICU materializing 512 matches
per call). The batched variant appends up to `windowSize` line ends per call,
advancing the resume point to the deferral unit.

[runtime-raw.json](runtime-raw.json) /
[runtime-samples-batched.csv](runtime-samples-batched.csv),
2026-07-13 15:04:58–15:06:32 UTC, hashes stable.

| Scenario | Effect | 95% CI | Better pairs | Verdict |
|---|---:|---:|---:|---|
| JavaScript throughput | **−1.967443%** | −3.868070%…−0.029238% | 1/15 | **slower** |
| TypeScript throughput | **−0.677687%** | −1.187579%…−0.165163% | 3/15 | **slower** |
| Real-Swift throughput | **+2.820421%** | +2.232827%…+3.411393% | 15/15 | faster |
| All-space JS comment | **+41.087803%** | +36.920721%…+45.381707% | 15/15 | faster |
| SQL / both incrementals | — | cross zero | — | neutral |

Variant 2's JavaScript interval is several times wider than this series'
norm, so its exact magnitude carries less weight — but its direction
corroborates variant 1's tight interval, and batching plainly did not cure
the regression, refuting the dispatch hypothesis.

## Verdict

**REJECTED & REVERTED.** The ECMAScript regression reproduces across two
variants and ~4.5% of aggregate wall-clock on the flagship workload cannot be
traded for a Swift-grammar gain under this project's no-resolved-regression
gate. The true mechanism of the ECMAScript slowdown is unattributed — the
candidate answers exactly the same match sequences (all checksums identical),
so it is an interaction between synthesized zero-width sequences and the
end-rule scan pattern, not a correctness difference. The ICU `$` semantics
probe and both differential data sets are retained here for any future
attempt; the profile evidence says the ceiling for such an attempt is ~1 ms
per run per grammar.

Machine: MacBook Pro Mac15,11, Apple M3 Max, 36 GB RAM, macOS 26.5.1
(Darwin 25.5.0), arm64; Swift 6.3.2. Baseline for both variants: the adopted
step-33 binary
(`05299888b90a3a8280d35c9e908c696f70d102756cce0d849f214c02d74f68bb`).
