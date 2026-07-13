# Changelog

## Unreleased

- Engine: keyword lookups probe a flat UTF-16 table straight from the
  input buffer — no per-word substring, `String` allocation, or Unicode
  hashing — and relevance-saturation counters are dense per-language
  arrays instead of a second `String`-keyed dictionary. Case-insensitive
  words containing non-ASCII units keep the full Unicode-folding path.
  Measured (15-pair paired A/B, 95% CI excluding zero): SQL +2.26%,
  real-Swift +1.14%, TypeScript +1.00%, JavaScript +0.93% throughput;
  controls neutral.
- Engine: the bare ECMAScript identifier rule is matched by an exact
  raw UTF-16 scan (its character classes are pure ASCII), eliminating
  whole-window ICU enumeration of every identifier. Case-insensitive
  rules keep ICU (its case folding reaches non-ASCII input units).
  Measured (15-pair paired A/B, 95% CI excluding zero): JavaScript
  +2.83%, TypeScript +1.99% throughput, JavaScript incremental −0.73%;
  non-ECMAScript controls neutral.
- Engine: the literal-table prefilters (Swift punctuated keywords,
  ECMAScript value starters) dispatch through a 128-slot directly-indexed
  bucket array instead of hashing a `Dictionary` at every input position.
  Measured (15-pair paired A/B, 95% CI excluding zero): real-Swift
  throughput +6.13%, JavaScript +1.48%; all controls neutral. Construction
  fails closed on non-ASCII first units, so rule semantics are unchanged.
- Engine: cached matches carry their capture groups inline
  (`.none`/`.group1`/`.icu`) instead of allocating an
  `NSTextCheckingResult` (plus a range buffer) per hand-synthesized
  match, and rule consultations read cached ranges without
  Objective-C dispatch. Measured (15-pair paired A/B, 95% CI excluding
  zero): JavaScript +4.78%, TypeScript +3.78%, real-Swift +1.82%, SQL
  +0.87% throughput; JavaScript incremental latency −1.58%. No behavior
  change; group semantics remain JavaScript `match[N]`-exact.

## 0.1.0 — 2026-07-10

Initial release.

### Highlights
- Pure Swift 6.1 port of highlight.js: 65 language grammars, token-exact
  output verified against the reference on a 375-fixture corpus.
- `NSRange`-based tokens and native `NSAttributedString` rendering — no
  JavaScript engine, no WebView, no HTML round-trip.
- Typed themes (GitHub and Xcode styles, light/dark/adaptive), theme
  registry with name lookup, and a one-call
  `attributedString(for:language:theme:)` convenience.
- `HighlightScope` — `Notification.Name`-style typed scope keys for
  themes: autocomplete and typo safety for the standard highlight.js
  scopes while custom grammar scopes stay expressible as string
  literals.
- Automatic language detection with a concurrent `async` overload
  (processor-bounded task window, cooperative parser/ICU cancellation,
  identical ranking when not cancelled, ~6× lower latency).
- Continuation-threaded incremental highlighting for editors: highlight
  chunks while carrying full nested/callback/keyword state, and stop forward
  propagation when states converge; cross-chunk regex-boundary limits are
  explicitly documented.
- Generation-aware lazy grammar registration: cold callers compile exactly
  once, failures are memoized, concurrent replacement cannot publish stale
  graphs, and warm canonical lookup uses one table hash.
- Thread-safe throughout (`Sendable`, `Synchronization.Mutex`); final
  concurrency, continuation, and registry stress selections are
  ThreadSanitizer-clean.
- Engine performance: per-rule windowed match caching plus
  shape-specialized prefilters, ~10× the naive port's throughput; every
  optimization (adopted and rejected) measured and documented.
- Custom-grammar hardening: a root-level `endsParent`, negative capture-group
  indexes, and integer-overflowing backreferences fail safely instead of
  reaching Foundation traps; each boundary has a direct regression test.
- Corrected the C++ `function.dispatch` port to match highlight.js's exact
  five-keyword exclusion set. Function-like `delete`, `static_assert`, and
  casts now receive the reference `built_in` scope and relevance.
- Re-audited all 65 grammars against highlight.js 11.11.1 and removed local
  drift in C#, CSS/Less/SCSS/Stylus, Diff, ECMAScript, Go, Groovy, JSON, Leaf,
  PHP, Python, Rust, and Shell. Adversarial fixture inputs remain, with their
  expectations regenerated from the pinned reference.
- Sub-language recursion now uses a bounded invocation-progress key (language,
  UTF-16 input length, and initial compiled mode): direct/mutual cycles stop,
  while whole-block and incremental XML self-delegation remain valid.
