# Benchmarks

Snapshot environment: MacBook Pro (Mac15,11), Apple M3 Max, 36 GB RAM,
macOS 26.5.1, Swift 6.3.2, measured 2026-07-10. The package declares Swift
tools 6.1 and compiles in Swift 6 language mode. Numbers below use production
`swift build -c release` binaries and are warm unless noted. Throughput is
**MU/s** — mega-UTF-16-units per second, roughly MB/s for ASCII text.
Reproduce with the bundled benchmark host:

```sh
swift build -c release
.build/release/highlight-bench 5 javascript                 # throughput
.build/release/highlight-bench 5 javascript --incremental   # per-line latency
.build/release/highlight-bench --auto 10                    # language detection
.build/release/highlight-bench --render 20 javascript       # attributed string
.build/release/highlight-bench 10 swift path/to/file.swift  # your own input
.build/release/highlight-bench --consumer-bench 5 all       # cache/render/TextKit consumers
```

`--consumer-bench` emits machine-readable JSONL for 40 old/new hunk pairs;
cold, warm, evicting, and single-flight caches; theme-only rerendering; token
and rendered-run budgets; retained cost per cached token and resident bytes per
attributed run; and, on macOS, an offscreen TextKit workload that installs the
overlay in `NSTextStorage`, forces layout, scrolls 40 deterministic viewports,
and forces drawing with `cacheDisplay`.

The first release-build snapshot for these workloads is recorded in
[`Benchmarks/Results/2026-07-23-consumer-highlighting`](Benchmarks/Results/2026-07-23-consumer-highlighting/README.md).
The 15-pair parser control against the restored green baseline is recorded in
[`Benchmarks/Results/2026-07-23-repository-aware-runtime`](Benchmarks/Results/2026-07-23-repository-aware-runtime/README.md);
it found no resolved regression across the existing parser workloads.

## Throughput (62 KB input, warm)

| Grammar | Input | MU/s |
|---|---|---|
| JSON | JS sample | 2.08 |
| SQL | JS sample | 2.07 |
| Swift | real Swift source | 2.15 |
| Swift | JS sample | 1.09 |
| TypeScript | JS sample | 0.85 |
| JavaScript | JS sample | 1.19 |

JavaScript, TypeScript, SQL, and real-Swift rows are candidate medians from
the latest production campaign (UTF-16 keyword lookup); JSON and
Swift-on-JS are representative warm snapshots from the same optimization
series. Values are rounded to two decimals. Use paired A/B data, not cross-row
arithmetic, to evaluate a change.

Throughput is grammar-bound, not input-bound: it scales with how many
rules the grammar races at each position and how match-dense the input
is for them. The JavaScript grammar (~40 root rules, expensive
value-context and arrow-function lead-ins) is the heaviest bundled
grammar; simple grammars run several times faster.

## Latency (the editor numbers)

| Scenario | Result |
|---|---|
| One line, continuation-threaded (JS, avg 62-unit lines) | **35 µs** |
| Blank line floor (JSON grammar → Swift grammar) | 5–17 µs |
| Auto-detect, 65 languages, warm, concurrent | **3.3 ms** (6.5× vs sequential) |
| Auto-detect, cold (compiles all 65 grammars) | ~24 ms |
| Cold start, one grammar (compile + first highlight) | ~4 ms |
| `NSAttributedString` for a 1 KB block | ~130 µs (7.6 MU/s) |

For a viewport of 60 lines, incremental re-highlighting costs ~2.2 ms —
well under half a 60 fps frame.

## Built-in theme access

Once-initialized built-in themes remove repeated dictionary, color, and font
construction from the convenience API. In the formal release A/B, direct
`.github` access fell from a 37,259.450 ns median to 3.014554 ns, registry
lookup from 86,350.069 ns to 42.099058 ns, and a small one-call
highlight-and-render workload from 83,847.150 ns to 45,159.6916 ns. Rendering
with a prebuilt theme and first theme access were neutral controls. See step 23
in [`Docs/PERFORMANCE.md`](Docs/PERFORMANCE.md) for paired confidence intervals,
iteration counts, and leak checks.

## Registry publication and contention

Registration generations compile at most once even when many tasks hit a cold
grammar together. The adopted v3 keeps cold/failure state behind a
per-generation `Synchronization.Mutex` and publishes the immutable graph in the
canonical registry slot under the existing global mutex. This makes a warm
canonical lookup one table hash and gives ThreadSanitizer a visible
happens-before edge.

Formal 15-pair production A/B results against the pre-generation registry:

| Scenario | Effect | 95% effect CI |
|---|---:|---:|
| Warm auto-detect, 64 languages | **−18.84% latency** | −19.62%…−18.05% |
| Cold contention, 16 tasks | **−53.28% latency** | −54.55%…−51.98% |
| Warm contention, 8 tasks | **−4.96% latency** | −6.90%…−2.97% |
| Warm highlight, 1 task | neutral | −1.53%…+1.55% |
| Warm contention, 32 tasks | neutral | −6.04%…+0.32% |

The baseline compiled 619 times across the 45 cold rounds; v3 compiled exactly
45 times. Two complete runtime campaigns (30 pairs per workload) found no
resolved JavaScript, TypeScript, real-Swift, SQL, or incremental regression.
See the [adopted v3 campaign](Benchmarks/Results/2026-07-10-registry-inline-publication/README.md)
and the retained [v1](Benchmarks/Results/2026-07-10-registry-mutex-v1-rejected/README.md)
and [v2](Benchmarks/Results/2026-07-10-registry-generation/README.md) rejections.

## How the engine gets there

The naive faithful port ran at 0.10 MU/s. The measured engine is ~10×
that, through changes that were each adopted or rejected on paired
before/after measurements:

- **Per-rule windowed match caching** instead of highlight.js's combined
  `(r1)|(r2)|…` re-scan: each rule's non-overlapping match sequence is
  materialized lazily in windows, so ICU invocations are proportional to
  *matches*, not engine iterations. (The combined-alternation design was
  re-tested as a short-input fast path and measured 5–6× slower — ICU's
  per-pattern start-condition optimization beats one giant interpreted
  alternation in every regime.)
- **Shape-specialized prefilters** for profiled-hot rules: candidates are
  located by scanning raw UTF-16 for a cheap *necessary* condition of the
  pattern (a literal `=>`, a colon after an identifier run, a digit with
  a non-word predecessor gated by each number variant's second unit, an
  identifier-head unit, branch-initial keyword letters on a word
  boundary), then confirmed with a single anchored ICU attempt. False
  candidates cost one attempt; false negatives are impossible by
  construction, and every prefilter is differentially fuzzed against raw
  `NSRegularExpression` enumeration with seeded corpora.
- **One UTF-16 index domain** — each run materializes or bridges its input to
  an `NSString` once, tokens store ranges instead of substring payloads, and
  adjacent same-scope tokens merge at emission. This avoids per-token string
  copies; it is not a blanket zero-copy claim, because Swift/Foundation
  bridging and attributed-string rendering may allocate.

Some things that measured *worse* and were rejected, for the record:
generalized FIRST-set prefiltering (candidate density kills it), a
combined-alternation fast path for short spans, struct→class and
closure-elimination micro-optimizations around the keyword loop (the
compiler was already ahead). The complete engineering history, including
exact numbers and verdicts for adopted and rejected steps, is checked in as
[`Docs/PERFORMANCE.md`](Docs/PERFORMANCE.md).

## Reproducible A/B protocol

For a performance change, freeze separate baseline and candidate executables
built with the same `swift build -c release` command. Warm every scenario,
interleave process-level A/B order, keep inputs and inner-run counts identical,
and include an unaffected grammar such as SQL as a negative control. Report
absolute medians, paired relative effects, confidence intervals, and token
counts. Retain the raw samples and statistics script. Treat intervals crossing
zero as neutral.

Do not compare a binary emitted by `swift test -c release` with one from
`swift build -c release`: the test build enables testability and is a different
configuration. The exact step-22 and built-in-theme campaigns, including
iteration counts and rejected measurements, are in
[`Docs/PERFORMANCE.md`](Docs/PERFORMANCE.md).
