# Performance log

This is an adopt/reject record, not a collection of numbers that can be
compared across unrelated rows. Historical steps used the workload and toolchain
available at the time; each verdict compares only adjacent binaries measured in
the same batch. Throughput is **MU/s** (mega-UTF-16-units per second; roughly
MB/s for ASCII). Every adopted parser change kept the 375-case fidelity suite
green and added differential coverage for hand-written matching paths.

The formal step-22 and theme-cache campaigns used a MacBook Pro (Mac15,11),
Apple M3 Max, 36 GB RAM, macOS 26.5.1, and Swift 6.3.2 on 2026-07-10. The
package declares `swift-tools-version: 6.1` and compiles in Swift 6 language
mode. Both sides were production binaries from `swift build -c release`.

Primary benchmark host:

```sh
swift build -c release
.build/release/highlight-bench 7 javascript
.build/release/highlight-bench 10 javascript --incremental
```

The opt-in test-target regression guards remain available with
`HIGHLIGHT_BENCH=1 swift test -c release --filter Performance`. Profiling uses
`sample` on the standalone host and per-rule cumulative instrumentation:

```sh
HIGHLIGHT_BENCH=1 swift test -c release \
  -Xswiftc -DDEBUG_MATCH_STATS --filter ruleCosts
```

| # | Change | Result | Verdict |
|---|--------|--------|---------|
| 0 | Baseline: faithful hljs port. One combined `(r1)\|(r2)\|…` alternation per mode, re-scanned from the parser position each step (`NSRegularExpression.firstMatch` per engine iteration). | **0.10** | baseline |
| 1 | Materialize input as CFString-backed `NSString` once per run; hoist the bridged `String` out of the loop. Rationale: a native Swift string stores UTF-8 and each ICU call transcodes it. | 0.10 → **0.13** (+30%) | **adopted** (also required by later steps) |
| 2 | Split the combined alternation into per-rule regexes with a per-run forward cache (`searchedFrom`/next-match). Profiling showed 75% of time in `icu::RegexMatcher::MatchAt` — the interpreter attempts every alternative at every position. | 0.13 → **0.49** (+277%) | **adopted** |
| 3 | ASCII FIRST-set prefilter for *all* analyzable rules: scan raw UTF-16 for candidate first units, attempt anchored ICU match at candidates; `\b`-prefix rules skip word interiors. | 0.49 → **0.51** (+4%) | **rejected** in general form — for dense heads (letters/digits) the per-candidate `NSRegularExpression` invocation (~1µs: objc dispatch, UText setup, result alloc) exceeds ICU's internal per-position loop. Instrumentation: 75k candidate attempts + 29k cache-miss searches per run. |
| 4 | Windowed match enumeration: per rule, lazily materialize its non-overlapping match sequence via `enumerateMatches` in windows of 512, walk with a monotonic cursor; overlap queries (post-veto rescans) fall back to a one-off search. `\B\|\b` (the default terminator, 54 rules in the JS grammar) short-circuits to a synthesized zero-width result — no ICU at all. | 0.49 → **0.49** (±0) | **adopted anyway** — throughput flat but ICU *call count* collapsed (29k → ~600/run) and per-call overhead (utext_setup, resetStack) left the profile; the remaining cost is true scan work, which step 6 attacks. Enables O(matches) instead of O(iterations) invocations, which matters for the editor use case. |
| 5 | Hybrid: sparse punctuation heads (≤12 ASCII chars, no alphanumerics/space/unicode) use candidate scanning inside the windowed cache; dense heads keep ICU enumeration. | 0.49 → **0.46** (−6% noise) | **kept, revised by 6** — sparse scanning is right only for genuinely rare candidates; space-headed rules were the regression (a candidate at every token gap). Space excluded from sparse eligibility in step 6. |
| 6 | Shape-specialized prefilters for the two worst measured rules (both from `CommonModes.comment`, present in every grammar): ① doctag `[ ]*(?=(TODO\|FIXME\|…):)` — 18.4 ms/run, ICU attempted every position because the rule can match zero-width; now candidates are literal-word occurrences, backed up over preceding spaces. ② JS templates `.?html\`` etc. — ~15 ms/run combined; now candidates are literal occurrences at offset 0/1. Both confirm with one anchored ICU match at the candidate, so semantics stay regex-defined. | 0.46 → **0.62** (+35%) | **adopted** |
| 7 | Copy-on-write fix: `RuleMatchCache.Entry` was a struct read out of / written back into the entries array around every mutation — each window append deep-copied the match arrays. Made `Entry` a reference type mutated in place (allocated lazily per touched rule). | — | **adopted** (measured together with 8) |
| 8 | Comment-prose gate: the english-prose relevance rule (`[ ]+(word…){3}`, worst measured rule at 13.9 ms) gets a candidate gate — spaces followed by two word-ish runs, a strict superset check in a tight UTF-16 loop; ICU confirms at candidates. Rule cost 13.9 → 5.8 ms. | 0.62 → **0.76** (+23% combined with 7) | **adopted** |
| 9 | `RuleMatchCache` struct → `final class`, dropping `inout` threading through `exec → scan → firstMatch`. Hypothesis: remove the dynamic exclusivity enforcement (`swift_beginAccess`, ~10% of samples). | 0.76 → **0.75** (neutral) | **adopted for code quality only** — the exclusivity samples did *not* drop (they come from Dictionary `_modify` accessors in the keyword loop, not the cache), so no perf win; kept because it removes three levels of `inout` and makes the cache reusable for the block editor. Recorded as neutral. |
| 10 | `HighlightEngine.Run` struct → `final class` (same exclusivity hypothesis; `Run` is captured mutably by the `enumerateMatches` keyword closure). | 0.75 → **0.73** (−3%) | **rejected & reverted** — measured *slower* (class allocation + indirection) and exclusivity samples rose, not fell. The checks originate from `Dictionary.subscript._modify` on `keywordHits`/`responseBoxes`, which a class `self` does not remove. A textbook case of a "looks-fast" change failing measurement. |

State after step 10: **0.75 MU/s**, 7.5× baseline. Cold start: 4 ms.
Incremental (block-editor line-by-line, continuation-threaded):
**~44 µs/line** — grammar-size-bound (≈40 root begin-rules attempted per
line), which is the architectural floor for a regex-per-rule engine.
(Step 14 tested — and rejected — the one idea that could beat that
floor; steps 15–16 push throughput to **0.85 MU/s**, 8.5× baseline.)

| # | Change | Result | Verdict |
|---|--------|--------|---------|
| 11 | `processKeywords`: replace the `enumerateMatches` closure (which captures the mutable `Run` `self` → dynamic exclusivity checks per field access, ~10% of samples) with `matches(in:)` + a plain `for` loop. | JS 0.78→0.76, SQL 2.22→2.17 (−2%) | **rejected & reverted** — the `[NSTextCheckingResult]` array `matches(in:)` allocates outweighs the exclusivity savings, on both a mode-heavy (JS) and a keyword-heavy (SQL) workload. Third measured attempt at the Dictionary-`_modify` exclusivity cost to fail; that cost is apparently cheaper than every alternative that removes it. |
| 12 | **Removed** the general sparse-punctuation-head prefilter and its ~450-line `RuleHeadSet` FIRST-set analyzer. A Linus-level "does this complexity earn its keep" pass measured it in isolation (env-gated): it is **net negative** — the punctuation ICU sees in real code (`{ } [ ] < > " '`) is frequent, so candidate scanning attempts the regex at too many positions, losing to ICU's internal `enumerateMatches` loop. | JS 0.78→0.79, JSON/CSS/XML/SQL +2–3% | **adopted (removal)** — faster on *every* workload, −650 LOC, 0 fidelity change (it was a pure search optimization). The three shape-specialized prefilters (doctag / prose / `.?<literal>` template) — which gave the real +35% — stay; they are cheap pattern-string checks, not a general analyzer. **Re-verified** after the sparse-head removal (env-gated): disabling all three costs −34% on JS (0.79→0.52) and −17% on comment-heavy code — they earn their keep decisively. |
| 13 | **Concurrent auto-detection**: `highlightAuto` gains an `async` overload that runs each candidate grammar in its own child task (`withTaskGroup`), reassembles results in registration order, and ranks with the same `selectBest` — so it returns *exactly* what the sequential overload returns (pinned by an equivalence test over 9 sample inputs × language/relevance/tokens/secondBest). Per-candidate `autoreleasepool` drains ICU match objects; cancellation skips unstarted candidates. | Paste-sized input (622 units, 65 languages): warm 23.1 → **3.7 ms** (6.2×), cold (includes 65-grammar lazy compile) 118.7 → 25.5 ms (4.7×). Hot path untouched: JS 0.75, SQL 1.78 MU/s — identical to HEAD re-measured under the same thermal conditions. | **adopted** — auto-detection is embarrassingly parallel (65 independent grammar runs) and was the last O(languages) sequential path. Latency-only change; the answer is bit-identical by construction (order-independent ranking over order-preserved slots). Sequential overload retained for synchronous callers and as the differential-test oracle. |
| 14 | **Combined-alternation fast path for short spans** (hljs's own `(r1)\|(r2)\|…` matcher, built lazily per scan offset with `\N` backreferences renumbered, behind a per-run threshold). Motivation: the per-line floor is O(root rules) — a blank JS line costs 13.2 µs, of which ~10 µs is 40 separate `enumerateMatches` calls; empty-line cost scales with grammar size (json 4.8 → python 11.4 → swift 17.1 µs). One combined ICU call should collapse that. Fully implemented and proven **bit-identical** (375-fixture both-paths equivalence + registry-wide ICU group-numbering validation + YAML `\2` renumbering + veto-resume offset forms all passed). | Real lines are where it loses: incremental JS **53.5 → 260 µs/line** at every threshold 48–512 (~5× slower); full documents 0.76 → 0.13 MU/s (~6× slower) even at 624 units. Only the degenerate blank-line case won. | **rejected & reverted** — ICU optimizes each individual pattern's start condition (literal prefixes, start sets) and `enumerateMatches` amortizes across matches; a 40-branch interpreted alternation re-attempted at every position destroys both advantages. The empty-line micro-benchmark was a mirage: it has ~2 positions to try. Confirms step 12's lesson from the opposite direction — per-rule batched enumeration beats combined alternation *in both regimes*, and upstream's matcher shape is wrong for ICU. Kept from the experiment: out-of-range capture-group clamps in `CallbackMatch`/`MultiMatch.groupRange` (JS `match[N]` → undefined; we returned NSRangeException) + regression test. |
| 15 | **`identBeforeColon` prefilter** for the ECMAScript object-key rule `[A-Za-z$_][0-9A-Za-z$_]*(?=:)` (4.02 ms in the step-14 profile — one whole-document enumeration attempting at every identifier). Scan the raw UTF-16 for `:` preceded by an identifier unit, walk back over the run (clamped at the resume point, then forward to the first startable unit so mid-run resumes stay exact), confirm with the anchored regex. Candidate starts are provably monotonic in colon order (an identifier run cannot span a colon), so the standard one-match-per-call `extendViaCandidates` machinery applies. | JS 0.75 → **0.79–0.80 MU/s** (+5–6%), incremental 53.5 → **48.3 µs/line** (−10%). | **adopted** — fourth shape-specialized prefilter; same architecture that won +35% before (anchor on a rare literal, let the regex decide). Colons are far rarer than identifiers. |
| 16 | **`arrowFunction` prefilter** for the profile's hottest rule (7.69 ms), the arrow lead-in `(\(params…\)\|ident)\s*=>` — nested-paren backtracking attempted at every `(` in the file. Every match ends at a literal `=>`; per arrow exactly one start is possible (back over `\s`, then to the balancing `(` or the leftmost startable unit of the `\w` run). Nested arrows make starts non-monotonic in arrow order (`(a,(b) => c) => d`), so candidates are batch-collected, sorted by start, and anchored-confirmed in order. Any non-ASCII unit touched by a walk defers the window to plain ICU enumeration — ICU's `\s`/`\w` are Unicode-aware (NBSP, é) and the ASCII walk must not guess. | JS 0.79 → **0.85 MU/s** (+7%; **+13% cumulative** with step 15), TS 0.63 → 0.66, incremental 48.3 → **45.1 µs/line** (−16% cumulative). SQL 1.83 / Swift 0.59 unaffected (no such rules). Warm concurrent auto-detect 3.7 → 3.3 ms. | **adopted** — validated by a dedicated differential suite: 1500-case seeded fuzz + 29 adversarial shapes (depth-4 parens, `a9c`, `$x`, NBSP/NEL/U+2028/Ogham-space, `==>`, nesting inversions) + exhaustive resume-position sweep, all pinned to raw `NSRegularExpression` enumeration; plus the 375 fidelity fixtures. |
| 17 | **`numberLiteral` prefilter** for the seven ECMAScript numeric variants (~7.4 ms combined in the step-14 profile). First attempt — naive shared candidates (digit with non-word predecessor, or `.`+digit) for all seven rules — measured **throughput-neutral**: ~900 number starts × 7 rules ≈ 6.3 ms of anchored `NSRegularExpression` attempts exactly cancels the enumeration savings, because ICU rejects a wrong head (`1…` for `\b0[xX]`) in ~2 compares while a full anchored attempt costs ~1 µs. Second attempt adds each variant's cheapest *necessary* condition as a gate: second unit for prefixed forms (`0x`/`0b`/`0o`/legacy octal), digit-run reaching `n` for BigInt, mantissa run reaching `[eE]` for the exponent form; plain decimal keeps ungated candidates (its matches are real). Gates are provably necessary (the first non-run unit after a match start *is* the `[eE]`/`n`), so false negatives are impossible; false positives just fail the anchored attempt. | Naive: JS 0.85 → 0.85 (±0). Gated: JS 0.85 → **0.89 MU/s** (+5%), TS 0.66 → 0.68, incremental 45.1 → **42.7 µs/line**. Same asymptotics as ICU on pathological inputs (`.1.1.1…` is O(n²) for both). | **adopted** (gated form) — the lesson: candidate quality beats candidate existence when several rules share a start set; per-rule attempt cost multiplies. Validated like steps 15–16: per-variant differential fuzz (7 × 600 seeded cases), adversarial corpus (`0x1Fn`, `1__0`, `٠5`, `.e5`, `089`), exhaustive resume sweep, grammar-drift pairing test, 375 fidelity fixtures. |
| 18 | **Swift-grammar prefilters + three-run prose gate.** A per-rule profile of the *Swift* grammar on real Swift code (the engine's own source) found: ① the `functionParameterName` zero-width lookahead and the plain `identifier` rule — both anchored on the giant Unicode-range alternation ICU cannot derive a start set from — at 29.5 + 11.3 ms; ② `(?=\b[A-Z])` at 5.0 ms; ③ residual comment-prose confirmations at 12.1 ms (the existing gate checked only two of the pattern's three required word-runs). Added `identifierHeadStart` (candidate: ASCII letter/`_` or ≥ 0x80 — exactly `identifierHead`'s ASCII part plus a safe non-ASCII superset) keyed on grammar-side named constants (`KwsSwift.identifierHeadAnchored` — engine and grammar share the string, drift impossible); `uppercaseBoundary` for `(?=\b[A-Z])`; and extended the prose gate to all three word-runs plus the mandatory trailing space. | Paired A/B, same thermal batch: real Swift code 0.41 → **0.45 MU/s** (+10%), Swift incremental 60.9 → 55.0 µs/line. The prose gate lifts *every* grammar: JS 0.85 → **0.97** (+14%), SQL 1.76 → **2.01** (+14%). | **adopted** — the Swift ident gains are capped by candidate density (identifiers are frequent, attempts ≈ matches); the cross-grammar prose win was the sleeper. Validated by a differential suite over all five patterns (unicode identifiers, combining marks, zero-width heads, 400 seeded fuzz cases each) and the fidelity fixtures. |
| 19 | **`wordStart` prefilter** for Swift's punctuated-keyword alternation (`\bas\?\B\|\btry!\B\|\bopen\(set\)\B\|…\|\bAny\b\|\bself\b`, 14.5 ms in the step-18 profile — a 17-branch alternation ICU attempts at every position). Every branch is `\b`-anchored and starts with a plain letter, so candidates are: first unit ∈ the branch-initial letter set, with a non-word predecessor. The pattern *and* the first-unit set are grammar-side constants (`KwsSwift.regexKeywordPattern` / `regexKeywordFirstUnits`), the set derived programmatically from the same keyword sources — drift impossible; a test pins every derived unit to an ASCII letter. `keywordWrapper` moved from the grammar builder into `KwsSwift` alongside them. | Real Swift code 0.45 → **0.51 MU/s** (+13%); Swift grammar on the JS sample 0.60 → **0.78 MU/s** (+30% — foreign text is all misses, exactly where the per-position alternation hurt most); Swift incremental 55.0 → 52.8 µs/line. Measured in a *worse* thermal batch than the baselines (JS read 0.91 vs 0.97), so gains are lower bounds. | **adopted** — first-letter gating on `\b`-anchored literal alternations generalizes; other grammars' keyword rules are candidates if they profile hot. Differential fuzz over the full alternation (keyword atoms, `xas?`, `énit`, zero-width joiners) + derivation sanity test. |
| 20 | **Hand-written ASCII confirm for Swift identifier shapes.** After step 18's gate, the step-19 profile showed the two Unicode-identifier rules still on top (33.8 + 15.6 ms): candidates were cheap but each *anchored ICU confirmation* cost 10–45 µs — the 50-branch Unicode class alternation is evaluated per character of the run. `identifierHeadStart` now carries a shape (`plain` / `withColon` / `parameterNameLookahead`); pure-ASCII candidates are decided by a hand walk (ident run → optional spaces → optional second ident → colon, per shape) and the match synthesized via `NSTextCheckingResult.regularExpressionCheckingResult` (all three patterns have zero capture groups, so a range-only result is indistinguishable from ICU's). Any ≥ 0x80 unit in a walk defers that candidate to one anchored ICU attempt. Definitive-`none` is sound because spaces and `:` cannot occur inside an ASCII word run — backtracking cannot create a match the walk misses. | Real Swift code 0.51 → **1.29 MU/s** (**2.5×**); Swift on the JS sample 0.78 → **1.09** (+40%); Swift incremental 52.8 → 49.8 µs/line. JS unaffected (0.92, thermal). | **adopted** — the first true hand-written matcher fragment; justified only because the per-attempt ICU cost was pathological, and safe only because the differential fuzz suites (unicode idents, combining marks, NBSP between idents, zero-width heads) pin it to raw ICU enumeration. Swift is now the fastest heavy grammar on real code. |
| 21 | **Paren-anchored prefilters + `&` composition + `(\s*)\(` synthesis.** Post-step-20 profiles: JS's `functionCall` negative-lookahead (3.48 ms), `(\s*)\(` params lead-in (3.37 ms); Swift's builtIn call (1.88 ms) and `\s+&\s+(?=[A-Z]…)` composition (3.11 ms). Three new mechanisms: ① `wordBeforeParen` — scan `(`, back over ASCII spaces (JS shape) and the ident run, anchored-confirm at each valid `\b` start inside the run. The differential fuzz caught two real ordering bugs here: `$` is in `identRe`'s class but not in `\w`, so interior word-boundary starts exist exactly where one side of a pair is `$` (`a$foo(` matches at `$foo`, `$f(` at `f`) — single-attempt-per-run was wrong. ② `ampersandComposition` — anchor on the rare `&`, require ≥1 ASCII space before, clamped attempt (space-run suffixes still satisfy `\s+`), Unicode space → window falls back to ICU. ③ `spacesThenParen` — every `(` is a match; both ranges (full + space-run group) computed by hand and synthesized with capture count 1, exactly ICU's shape. Grammar-side named constants throughout (`Ecmascript.functionCallPattern`, `KwsSwift.builtInCallPattern`/`protocolCompositionPattern`). | JS 0.97 → **1.00–1.03 MU/s** (crossed 1.0), TS 0.68 → **0.75** (+10%), real Swift 1.29 → **1.59–1.66** (+27%), JS incremental 42.3 → **40.4 µs/line**. SQL 1.94 unaffected. | **adopted** — dot-anchored rules were considered and *rejected without implementation*: `.` is frequent in real code, exactly the regime where step 12 measured general punctuation-candidate scanning as net-negative. |
| 22 | **Exact literal dispatch for the two remaining profiled rule families.** ① Swift's punctuated-keyword alternation is parsed at compile time into ordered literal buckets and matched directly in UTF-16, including its `\b`/`\B` tail; non-ASCII boundary context falls back to one anchored ICU attempt. This replaces step 19's first-letter gate plus an ICU confirmation at every candidate. ② ECMAScript's dense value-container lead-in `(RE_STARTERS|case|return|throw)\s*` is parsed into an order-preserving operator table (`!` must beat `!=`, matching ICU alternation order); operator matches and both capture groups are synthesized, while keyword candidates and Unicode whitespace fall back to ICU. Structural parsers fail closed on any non-literal regex syntax, and differential tests cover Unicode boundaries, seeded fuzz, captures, overlap/resume queries and every source-table branch. | 15 interleaved process-level pairs after a full scenario warm-up; 7 inner runs (incremental: 10,005 line calls). Median A→B: JS **0.99→1.05 MU/s**, TS **0.74→0.76**, real Swift **1.27→1.52**; JS incremental **40.83→37.86 µs/line**, Swift incremental **46.55→43.71 µs/line**. Paired geometric mean: JS **+5.70%** (95% CI +4.70…+6.71), TS **+3.33%** (+2.70…+3.96), real Swift **+18.75%** (+17.70…+19.81); JS latency **−7.49%** (−8.06…−6.90), Swift latency **−6.10%** (−6.70…−5.50). SQL-only 15×25-run control: **−0.31%**, CI −0.74…+0.13 (neutral). Token counts were identical in every sample. | **adopted** — all affected scenarios moved in the expected direction in 15/15 pairs; the control interval crosses zero. Baseline `3a9d1ff`; both binaries came from `swift build -c release`. |
| 23 | **Cache immutable built-in themes and registries.** Built-in GitHub/Xcode light, dark, and adaptive themes, the name registry, and its sorted names changed from computed factories to once-initialized `static let` values. Public callers still receive value types; copy-on-write tests mutate returned `styles` dictionaries and registry copies to prove the cached values remain independent. Concurrent-read and adaptive light/dark-resolution tests pin thread safety and behavior. | Formal release A/B. Warm median: direct theme access **37,259.450→3.014554 ns/op** (15 pairs; paired latency **−99.9920734%**, 95% CI −99.9923488…−99.9917881); registry lookup **86,350.069→42.099058 ns/op** (15 pairs; **−99.9510026%**, CI −99.9514172…−99.9505844); one-call highlight+default-theme render **83,847.150→45,159.6916 ns/op** (15 pairs; **−46.26551%**, CI −46.75097…−45.77563). Pure rendering with a prebuilt theme was neutral: median **11,176.325→11,308.754 ns/op** (15 pairs), paired **+0.75937%** (CI −1.22937…+2.78816). First theme access was also neutral across 30 fresh-process pairs: median **193,541.5→182,521 ns**, paired **−3.1798%** (CI −11.18875…+5.55143). | **adopted** — it removes repeated construction on the warm public path without changing renderer throughput or cold-start latency. Direct getter batches used 5,000 baseline versus 20,000,000 candidate iterations; registry batches used 3,000 versus 5,000,000; unequal counts were chosen only to obtain stable wall time after the multi-order-of-magnitude win, and all results were normalized per operation with identical per-operation checksums. One-call used 5,000/side and pure-render 20,000/side. `leaks --atExit` reported 0 leaks for both binaries. |
| 24 | **Make continuations complete, generation-owned editor states and close every ownership/recursion hole.** `Continuation` now retains its exact compiled-language generation and the full nested mode/callback/sub-language/keyword-saturation state; foreign or stale generations restart safely. Callback dictionaries are immutable snapshots keyed by activation identity. Closed embedded-language state is pruned only at chunk boundaries, preserving highlight.js's within-pass semantics. Compiled cyclic mode graphs are dismantled on success and every failure path, registration releases retired generations outside the global mutex, and ancestry bounds recursive delegation by compiled-language identity, UTF-16 input length, invocation initial-mode identity, and a depth-64 ceiling. It rejects direct/mutual/auto cycles while permitting strictly shrinking whole-block XML and a finite set of equal-sized incremental invocation states. Keyword hit counts saturate at seven and zero-relevance entries allocate no counter. A frame is allocated only after begin callbacks accept it. | Formal production A/B against step 23, 15 interleaved pairs and no exclusions. Median baseline→candidate: JS **1.056796→1.054237 MU/s**, TS **0.762522→0.776114**, real Swift **1.738240→1.738240**, SQL **1.948622→1.968354**; JS incremental **37.981009→37.681159 µs/line**, Swift incremental **44.477761→43.878061**. Paired effects (95% CI): JS **+0.434505%** (−0.726560…+1.609148), TS **+0.718470%** (−0.138330…+1.582622), real Swift **+1.073631%** (−0.005230…+2.164133), SQL **+2.801872%** (−1.408549…+7.192103), JS latency **−4.257312%** (−11.046605…+3.050169): all neutral. Swift incremental latency improved **−0.880386%** (−1.516251…−0.240415). All 90 checksum/shape comparisons matched. | **adopted** — this is primarily a correctness, bounded-memory, and block-editor convergence repair; it has no resolved regression and one small resolved latency improvement. The full method, hashes, 90-row sample table, and no-exclusion disturbance record are retained in the [state-machine campaign](../Benchmarks/Results/2026-07-10-state-machine/README.md). |
| 25 | **Generation-aware registry, mutex v1.** One immutable `Entry` per registration generation owns a `Synchronization.Mutex<CompilationState>` so concurrent cold callers compile once, failures are memoized, replacement cannot publish an old graph, aliases have explicit ownership, factories cannot re-enter compilation, and retired graphs are released outside the global table lock. | Registry: auto **−18.045766%**, cold contention **−52.318362%**, warm 8-reader **−11.456401%**; but warm 32-reader latency regressed **+3.506788%** (95% CI +1.194844…+5.871552). Runtime: JavaScript throughput regressed **−2.180742%** (−3.624356…−0.715504). | **rejected & replaced** — both resolved hot-path losses fail the gate despite the correctness/cold gains. All 180 paired observations and hashes are retained in the [mutex-v1 campaign](../Benchmarks/Results/2026-07-10-registry-mutex-v1-rejected/README.md). |
| 26 | **Generation publication cache v2.** Successful graphs are published through the registry's global mutex into an `ObjectIdentifier(entry) → CompiledLanguage` table. Warm readers take one lock rather than the Entry mutex; auto-detection captures all generation snapshots under one lock. The otherwise-correct `AtomicLazyReference` variant was separately rejected because Swift 6.3.2 TSan reports false publication races. | Registry: auto **−17.215786%**, cold **−52.402955%**, warm 32-reader **−4.797875%**. Runtime nevertheless regressed: JavaScript **−1.435524%** (CI −2.289676…−0.573905; lost 14/15) and TypeScript **−0.898650%** (−1.499526…−0.294109; lost 13/15). | **rejected & replaced** — a second hash/probe on the canonical warm path did not clear the real-workload bar. Exact raw evidence is in the [publication-v2 campaign](../Benchmarks/Results/2026-07-10-registry-generation/README.md). |
| 27 | **Inline generation publication v3.** Store the published graph beside its canonical `Registration`, eliminating v2's second dictionary hash while retaining the per-Entry cold/failure mutex and the global-mutex publication HB edge. Canonical warm lookup is one table lookup; alias lookup verifies and retains its exact generation. | Registry primary 15-pair A/B: auto **−18.838459%** (CI −19.620823…−18.048481), cold **−53.282884%** (−54.546825…−51.983797; baseline 619 builds vs v3 45), warm 8-reader **−4.956856%** (−6.904654…−2.968306); warm highlight, 1-reader, and 32-reader neutral. Primary runtime: JS +0.321450%, TS +0.310060%, SQL +0.017920%, both incremental controls neutral. An independent second 15-pair runtime campaign and pooled 30-pair intervals classify all six controls neutral. | **adopted** — v3 keeps the exact cold/concurrency correctness gains and removes every resolved v1/v2 runtime loss. No observations were excluded; opposing 2× real-Swift stalls and all other disturbances remain in the [v3 campaign](../Benchmarks/Results/2026-07-10-registry-inline-publication/README.md). |

| 28 | **Inline match-group representation.** The cache stored one `NSTextCheckingResult` per cached match; the four hand-written prefilter paths (`(\s*)\(` lead-in, Swift punctuated keywords, value-starter operators, Swift identifier shapes) allocated one per real match — plus a heap `[NSRange]` for the two multi-group shapes — only to carry capture groups the parse loop rarely reads. Replaced by an inline enum `MatchGroups` (`.none` / `.group1(length:)` — both synthesized group shapes are "group 1 = leading N units" / `.icu(result)`), resolved on demand by one shared accessor with JS `match[N]` semantics used by `MultiMatch`, `CallbackMatch`, and the differential tests. Two mechanism-level effects apply to every grammar: consulting a rule's next cached match reads the parallel `starts`/`ends` ints instead of an ObjC `.range` dispatch, and storing an ICU match reads `.range` once instead of three times. | Formal 15-pair A/B, no exclusions, hashes stable. Median baseline→candidate: JS **1.070912→1.122490 MU/s**, TS **0.777755→0.808091**, real Swift **1.932066→1.973916**, SQL **1.985053→2.005108**; JS incremental **36.948105→36.356951 µs/line**, Swift incremental **42.033383→41.916184**. Paired effects (95% CI): JS **+4.781175%** (+4.533866…+5.029068, 15/15), TS **+3.775524%** (+3.577960…+3.973464, 15/15), real Swift **+1.815625%** (+1.083954…+2.552593, 14/15), SQL **+0.865841%** (+0.444986…+1.288460, 13/15), JS incremental **−1.583964%** (−1.918595…−1.248192, 15/15); Swift incremental (−0.228694%, CI crosses zero) and the all-space prose control (+2.442851%, CI crosses zero) neutral. All checksums matched; `leaks --atExit` 0 leaks. | **adopted** — every affected scenario moved in the expected direction with intervals excluding zero and no scenario regressed; the SQL control improving confirms the grammar-independent mechanism. Raw samples, CSV, and hashes in the [match-groups campaign](../Benchmarks/Results/2026-07-13-match-groups/README.md). |

| 29 | **Direct-index literal-table dispatch.** `OperatorTable`/`KeywordTable` probed a `Dictionary<UInt16, [[UInt16]]>` per input position (`extendValueStarters` hashes every character of the document; `extendPunctuatedKeywords` every candidate). A post-28 `sample` profile put `__RawDictionaryStorage.find` + `Hasher._hash` among the top non-ICU frames on both JS and real Swift. Replaced with a 128-slot directly-indexed bucket array — dispatch is one bounds-checked load; construction fails closed on a non-ASCII first unit (rule keeps ICU enumeration); per-bucket alternation order unchanged. | Formal 15-pair A/B vs step 28, no exclusions, hashes stable. Real Swift **1.998466→2.114211 MU/s**, paired **+6.132487%** (95% CI +5.825841…+6.440022, 15/15); JS **1.123135→1.145095**, **+1.480523%** (+1.057850…+1.904964, 15/15). TS (−0.001693%), SQL (+0.196874%), both incrementals, and the prose control neutral (CIs cross zero). SQL has no literal-table rule — its neutrality localizes the mechanism. All checksums matched; `leaks --atExit` 0 leaks. | **adopted** — both table-dispatch workloads improved 15/15 with intervals excluding zero; all controls neutral. Raw samples and hashes in the [table-dispatch campaign](../Benchmarks/Results/2026-07-13-table-dispatch/README.md). |

| 30 | **Exact ASCII scan for the bare ECMAScript identifier.** The post-28 profile ranked `[A-Za-z$_][0-9A-Za-z$_]*` fourth (1.99 ms/run, whole-window ICU enumeration — every identifier is a match). Both classes are pure ASCII with no assertions, so the raw UTF-16 scan is the regex itself; matches synthesize `.none` groups with zero ICU calls on the sequence path. Gated to case-sensitive rules — ICU `.caseInsensitive` folds *input* units (U+212A → `[a-z]`), invisible to an ASCII walk; a differential test pins the Kelvin-sign case. Overlap/pre-scan queries still go to ICU. New suite: adversarial shapes, 1,500-case seeded fuzz, exhaustive resume positions, surrogate pairs. | Formal 15-pair A/B vs step 29, no exclusions, hashes stable. JS **1.148093→1.181754 MU/s**, paired **+2.833921%** (95% CI +2.527751…+3.141005, 15/15); TS **0.820844→0.837927**, **+1.988112%** (+1.715635…+2.261319, 15/15); JS incremental **35.697172→35.575154 µs/line**, **−0.731479%** (−1.350070…−0.109009). Real Swift (−0.004664%), SQL (−0.200829%), Swift incremental, prose control neutral — Swift/SQL don't contain the rule, localizing the mechanism. `leaks --atExit` 0 leaks. | **adopted** — both ECMAScript workloads improved 15/15 with intervals excluding zero; all non-ECMAScript controls neutral. Raw samples and hashes in the [ascii-identifier campaign](../Benchmarks/Results/2026-07-13-ascii-identifier/README.md). |

| 31 | **UTF-16 keyword lookup + dense hit counters.** `processKeywords` paid, per word in every grammar: an `NSString`→`String` substring bridge, a Unicode `String` hash for the keyword dictionary, `.lowercased()` when case-insensitive, and a second `String`-keyed dictionary for saturation hits. `CompiledKeywords` now keeps the `String` dictionary as source of truth/fallback plus a flat UTF-16 open-addressing table (FNV-1a, linear probe, ≥2× occupancy) probed straight from the input units. Case-sensitive: raw units, exact for non-ASCII keywords. Case-insensitive: ASCII `A-Z` folded in the probe; any word with a ≥0x80 unit routes to the `String` path (full Unicode folding — U+212A→`k` pinned by test). Hits: `[String: Int]` → dense `[UInt8]` indexed by per-language word ids shared across modes (hljs counts per word text per run); continuations carry the generation-owned array. | Formal 15-pair A/B vs step 30, no exclusions, hashes stable. SQL **2.020329→2.067604 MU/s**, paired **+2.258396%** (95% CI +1.612053…+2.908850, 14/15); real Swift **+1.142328%** (+0.569585…+1.718332, 12/15); TS **+0.999977%** (+0.545559…+1.456448, 14/15); JS **+0.928600%** (+0.564417…+1.294103, 13/15). Both incrementals and prose control neutral. `leaks --atExit` 0 leaks (SQL + real Swift). | **adopted** — every throughput workload improved with intervals excluding zero; the effect is largest exactly where keyword density and case folding were the cost (SQL). Raw samples and hashes in the [keyword-units campaign](../Benchmarks/Results/2026-07-13-keyword-units/README.md). |

| 32 | **firstMatch cursor-walk local hoist.** Post-31 profile: ~6% of JS samples in dynamic exclusivity (`swift_beginAccess`/`AccessSet`/TLS), ~4% in `firstMatch`. Hypothesis: the per-iteration `entry.cursor += 1` class-property modify access pays a dynamic check; hoist the walk onto a local with one write-back. | First campaign invalid (CoreSimulatorService at ~64% CPU — quiet-machine precondition violated; TS CI −17.9…+8.3, retained as `runtime-raw-disturbed.json`). Clean re-run (ps-verified quiet): JS **−1.395297%** (95% CI −1.722911…−1.066590, 1/15), TS **−0.981534%** (−1.340462…−0.621300, 2/15), Swift incremental latency **+0.525139%** (+0.043197…+1.009402); others neutral. | **rejected & reverted** — the fourth exclusivity-motivated attack to measure neutral-to-negative (after 9, 10, 11): the profile cost is real but the unconditional store + hoisted count defeat better codegen. Direct property walk restored with a comment citing the [cursor-hoist campaign](../Benchmarks/Results/2026-07-13-cursor-hoist/README.md). TSan re-verified the step-31 state (17 stress/registry tests, zero warnings) on both trees. |

| 33 | **Whitespace-run synthesis for bare `\s+` rules.** Grammars carry bare `\s+` modes (e.g. the JS function-params list), previously whole-window ICU enumerations. ASCII `\s` is exactly 0x09–0x0D + 0x20, so runs synthesize as `.none` matches; any ≥0x80 unit during search or at run end defers the window to ICU (`\s` matches U+0085/U+00A0/U+1680/U+2000–200A/U+2028/29/U+202F/U+205F/U+3000). Differential suite: adversarial Unicode-space shapes, 1,500-case seeded fuzz, exhaustive resume positions. | Formal 15-pair A/B vs step 31 (ps-verified quiet). JS incremental **35.321731→34.848155 µs/line**, paired **−1.368569%** (95% CI −1.677463…−1.058704, 15/15) — the editor path, where per-line scans can't amortize per-window enumeration. TS **+0.240057%** (+0.010660…+0.469980, marginal). JS/Swift/SQL throughput, Swift incremental, prose control neutral; no regression. `leaks --atExit` 0 leaks. | **adopted** — a clean editor-latency win with tight interval and 15/15 pairs; all controls neutral. Raw samples and hashes in the [whitespace-runs campaign](../Benchmarks/Results/2026-07-13-whitespace-runs/README.md). |

### Measurement validity notes

The candidate-side theme microbenchmarks can be reproduced directly; run
`theme-cold` in a new process for every observation:

```sh
swift build -c release
BIN=.build/release/highlight-bench
"$BIN" --theme-bench theme-get 20000000
"$BIN" --theme-bench registry-get 5000000
"$BIN" --theme-bench one-call 5000
"$BIN" --theme-bench pure-render 20000
"$BIN" --theme-bench theme-cold 1
```

Each line reports scenario, iteration count, nanoseconds per operation, and a
checksum. Use the baseline iteration counts in row 23 when measuring the
pre-cache implementation.

- Formal comparisons use two separately frozen executables produced by
  `swift build -c release`, a full warm-up of every measured scenario, and
  interleaved process-level A/B order. Reported percentage effects are paired
  geometric-mean ratios; confidence intervals that cross zero are labeled
  neutral.
- The step-22 and theme-cache notes include the reported 95% intervals but not the
  raw samples, statistics script, or exact interval-construction method. The
  intervals above are therefore an honest historical record, not independently
  reproducible from this repository. Future campaigns must check in the raw
  machine-readable results and analysis script before claiming a CI.
- Steps 24–27 follow that stronger rule: the reusable runners, all paired
  samples, exact interval construction, input and executable hashes, checksums,
  and workload shape are checked in with each result. Rejected v1/v2 data is
  retained beside the adopted v3 campaign.
- A registry prototype published the immutable compiled graph through
  `Synchronization.AtomicLazyReference` and kept failures behind a separate
  mutex. Its memory ordering is appropriate for lazy publication, but the
  Apple Swift 6.3.2 runtime did not expose that happens-before edge to TSan:
  the isolated `StressTests.contendedLazyCompilation` run passed its assertion
  but exited 1 with **5 race warnings**; the combined Registry/Incremental/
  Stress selection reported **6 warnings**. A separate 24-byte immutable-box
  probe using only `AtomicLazyReference.storeIfNil`/`load` reproduced **1
  warning**, excluding HighlightKit mutation as the cause. The lock-free form
  was nevertheless **rejected before performance sampling**: a sanitizer gate
  that cannot distinguish publication from a race is not an actionable safety
  gate. Mutex-v1 then passed the same 34-test sanitizer selection with zero
  warnings but failed formal performance sampling (step 25). Adopted v3 keeps
  a per-generation `Synchronization.Mutex<CompilationState>` only for cold
  compilation/failure state and publishes the immutable graph through the
  registry's existing global mutex. Its final 64-test / 4-suite TSan run took
  30.885 s and reported **0 warnings**; warm and contended performance is
  measured in step 27 rather than inferred from a primitive's name.
- An early continuation/lifecycle batch accidentally compared a production
  `swift build -c release` executable with one emitted by
  `swift test -c release`. The latter was built with `-enable-testing` and was
  32 KB larger; its apparent 1–2% slowdown also affected the SQL negative
  control. That batch was **rejected as a configuration mismatch** and none of
  its values are used above.
- Token counts or benchmark checksums must match in every pair. A throughput
  result is invalid if observable output differs.

The standalone publication probe used for the `AtomicLazyReference` decision
contains no HighlightKit code:

```swift
import Synchronization

final class Box: Sendable {
    let value: Int
    init(_ value: Int) { self.value = value }
}

@main enum Probe {
    static func main() async {
        let reference = AtomicLazyReference<Box>()
        await withTaskGroup(of: Int.self) { group in
            for index in 0..<64 {
                group.addTask {
                    let box = reference.load()
                        ?? reference.storeIfNil(Box(index))
                    return box.value
                }
            }
            for await _ in group {}
        }
    }
}
```

Compile and run it with
`swiftc -parse-as-library -sanitize=thread probe.swift -o probe && ./probe`.
On the recorded toolchain it exits 134 after one warning on the immutable
`Box.value` read/write pair.

### Swift ownership and dispatch audit

The Swift 6.1 ownership features were reviewed at the same time as the ARC/COW
profile; they were not added decoratively:

- Normal `Copyable` parameters are borrowed for the duration of a call unless
  the API consumes them. The parser does not need to invalidate its caller's
  `String`, token array, theme, or continuation, so spelling `consuming` would
  change ownership semantics without removing the required retained state.
  Explicit `borrowing` is used only in benchmark checksum consumers, where it
  prevents the measurement observer itself from adding ownership traffic.
- The package builds the internal engine with release whole-module
  optimization. Its concrete structs/classes have no protocol-existential hot
  dispatch, and private leaf helpers are already visible to specialization.
  `@usableFromInline` would widen implementation ABI for no call-site benefit;
  `@inline(__always)` remains limited to the measured matcher leaf operations.
- Identity-bearing compiled modes, per-rule cache entries, resumable-state
  nodes, and registry generations are `final` reference types where shared
  lifetime is the data model. The mutable parse `Run` remains a value: the measured
  struct→class experiment was **3% slower** and is rejected in step 10.
  Conversely, changing `RuleMatchCache.Entry` from a repeatedly copied COW
  value to one lazily allocated reference removed real deep copies (steps 7–8,
  **+23% combined**).
- `inout` remains only where mutation is genuinely single-owner (compiler
  context and matcher cursor). Removing three levels of cache `inout` through a
  reference type was throughput-neutral (step 9) but simplified exclusivity;
  attempts to remove the keyword closure/Dictionaries' `_modify` access by
  allocating arrays or a class measured **−2%** and **−3%** (steps 11 and 10)
  and were reverted.

This leaves ownership annotations as contracts rather than optimizer folklore:
every non-default spelling in a hot path either prevents benchmark distortion
or corresponds to a measured data-structure decision.

## Where the time goes (after step 22)

Step 22 removes the previous RE_STARTERS and Swift punctuated-keyword
ICU-confirmation costs. The next allocation candidate is now explicit:
the synthesized value-start matches still allocate a three-element
`[NSRange]` plus an `NSTextCheckingResult` for every real operator match.
That follow-up is measured separately; it is not folded into step 22.
(Resolved by step 28: synthesized matches no longer allocate at all, and
the win generalized — the per-consultation `.range` dispatch mattered for
every grammar, not just the synthesized rules.)

## Where the time goes (after steps 15–16)

The step-14 profile ranked: arrow lead-in 7.69 ms, RE_STARTERS 6.21 ms,
prose confirmations 6.11 ms, object-key `(?=:)` 4.02 ms, numbers ~7.4 ms
across three variants, BUILT_IN lookahead 3.46 ms. Steps 15–16 removed
the arrow and object-key entries (+13%). Remaining top rules: RE_STARTERS
(mostly real matches — 7.7k/run), prose confirmations (real relevance
work), number literals, BUILT_IN. The section below describes the
pre-15 state and remains accurate about the non-ICU 30%.

## Where the time goes (after step 12)

At 0.75 MU/s the profile is **~70% ICU** (`RegexMatcher::MatchAt` /
`MatchChunkAt` / `find`) doing genuine match work on the expensive rules
(`RE_STARTERS` value container, arrow-function paren counting, number
literals, residual prose confirmations). The remaining ~30% splits
roughly: ~12% malloc/free (per-run `NSString` + units + cache-entry
arrays), ~10% Dictionary exclusivity + ARC around `NSTextCheckingResult`,
~8% engine dispatch. Every attempted attack on the non-ICU 30% measured
neutral-to-negative (steps 3, 9, 10) — the compiler already handles it,
or the cost is intrinsic to `NSRegularExpression`. Beating the ICU floor
would require replacing the hottest rules with hand-written UTF-16
matchers validated by differential testing; deferred as high-risk for
the fidelity guarantee, and unnecessary given the editor budget (one
line at 44 µs is 0.3% of a 60 fps frame).

## Profile after step 8

Top remaining rules are flat (3–6 ms each) and dominated by real match
work: the `RE_STARTERS` value-container (7.7k actual matches/run), the
prose rule's residual ICU confirmations, the arrow-function
paren-counting lead-in, and number literals. Rule-level specialization
is past the knee; the next wins are engine-side (ARC around
`NSTextCheckingResult`, synthesized-result allocation for `\B|\b`
terminators, keyword-table dispatch for `beginKeywords` rules).

## Profile after step 6 (historical)

- ~47% ICU (down from 75%): dominated by the comment-prose rule
  `[ ]+((?:I|a|is|…){3}` (13.9 ms/run — inherently backtracking-heavy,
  exists for relevance scoring), the `RE_STARTERS` value-container
  alternation (5.9 ms, mostly real matches), and the arrow-function
  paren-counting lead-in (5.7 ms).
- ~11% ARC traffic (`swift_retain/release`, `objc_retain/release`,
  bridge retain/release) around `NSTextCheckingResult` storage and the
  candidate closures.
- Remainder: engine dispatch, keyword scanning, allocation.

## Candidate next steps (by measured ceiling)

1. Comment-prose rule (13.9 ms): exact hand-written matcher validated
   by differential testing against `NSRegularExpression`, or accept as
   the cost of hljs relevance fidelity.
2. ARC/allocation diet in `RuleMatchCache` (parallel arrays already
   avoid struct-of-refs copies; storing ranges and deferring
   `NSTextCheckingResult` retrieval could halve retain traffic).
3. Keyword-alternation rules → shared word-table dispatch (exact
   `\b(w1|w2|…)(?!\.)(?=\b|\s)` semantics via UTF-16 word scan + set
   lookup) — benefits every grammar's `beginKeywords` modes.

## Non-regression

`PerformanceTests.throughput` asserts > 0.3 MU/s as a floor;
`firstHighlightIncludesCompileCost` asserts cold start < 500 ms. Both
run in release only (`HIGHLIGHT_BENCH=1`).

## Rendering path (NSAttributedString)

Profiled separately (`highlight-bench --render`). `attributedString(for:
theme:)` runs at **7.5 MU/s (JS) / 10.7 MU/s (Swift)** — ~10× faster than
highlighting, so it is not the editor bottleneck (a 1 KB code block
renders in ~130 µs). The profile is dominated by `NSAttributedString.
addAttributes` (`objc_msgSend`, `NSAttributeDictionary`) — inherent to
producing an `NSAttributedString` and not reducible without changing the
output type. A per-scope style-resolution cache (to skip the dot-path
`title.function`→`title` walk) was tried and measured **neutral** (7.47→
7.48) — the walk isn't the cost — so it was reverted to keep the render
code simple. The emitter already merges adjacent same-scope runs, so
consecutive tokens differ in scope and range-batching `addAttributes`
would not help.
