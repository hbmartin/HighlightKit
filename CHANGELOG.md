# Changelog

## Unreleased

- API: language descriptors now carry normalized extension, exact-filename,
  and interpreter metadata. The async repository resolver handles overrides,
  shebangs, compound extensions, and content-assisted ambiguous extensions.
- Breaking: replaced nullable-language and silent-fallback entry points with
  throwing `LanguageSelection` APIs, cancellable async named highlighting,
  explicit parser options, and token budgets. Results now report UTF-16 source
  length and omitted-token counts.
- Languages: added a first-party Fish grammar based on Fish source/docs at
  20569c4. It is excluded from unrestricted autodetection but remains
  available by name, extension, and shebang.
- Languages: added Zig from highlightjs-zig at 6225ff9.
- Languages: added Terraform/HCL from highlightjs-terraform at eb1b966.
- Languages: added Protocol Buffers from the pinned highlight.js 11.11.1 grammar.
- Languages: added GraphQL from the pinned highlight.js 11.11.1 grammar.
- Languages: added Elixir from the pinned highlight.js 11.11.1 grammar.
- Build: moved the large Swift grammar factory behind an explicitly typed
  construction boundary and replaced its remaining long array expressions
  with incremental appends. This restores Swift 6.2.4/Xcode 26.3 builds
  without changing grammar tokens.

## 0.2.0 — 2026-07-14

- Fixed: a keyword listed under two scope groups of the same mode now
  resolves to a deterministic winner (sorted scope order) instead of
  varying with Swift `Dictionary` iteration order across processes.
  highlight.js resolves such duplicates by object insertion order, which
  the grammar model cannot observe — see FIDELITY.md. No bundled grammar
  declares a duplicate.
- Fixed: four matcher prefilters whose ASCII candidate scans cannot see
  ICU case folding (identifier-before-colon, number literals, the Swift
  uppercase lead-in, and word-before-paren) now decline case-insensitive
  rules and fall back to raw ICU enumeration. All bundled grammars
  declare these rules case-sensitively; this hardens the public
  custom-grammar API only.
- Fixed: grammar compilation leaked raw-mode reference cycles that
  variant expansion had detached from the grammar root (self-recursive
  variant-carrying modes, e.g. Scheme's nested lists — ~90 KB leaked per
  cold 65-language auto-detection). Teardown now reaches every mode
  considered for expansion explicitly; a weak-reference regression test
  pins the exact shape.
- Engine: bare `\s+` rules synthesize ASCII whitespace runs directly and
  defer to ICU whenever a non-ASCII unit could participate (`\s` is
  Unicode-aware). Measured (15-pair paired A/B): JavaScript incremental
  latency −1.37% (95% CI excluding zero, 15/15 pairs); no regressions.
- Engine: keyword lookups probe a flat UTF-16 table straight from the
  input buffer — no per-word substring, `String` allocation, or Unicode
  hashing — and relevance-saturation counters are dense per-language
  arrays instead of a second `String`-keyed dictionary. Case-insensitive
  words containing non-ASCII units keep the full Unicode-folding path.
  Measured (15-pair paired A/B, 95% CI excluding zero): SQL +2.26%,
  real-Swift +1.14%, TypeScript +1.00%, JavaScript +0.93% throughput;
  controls neutral.
  Behavior note for custom grammars: case-sensitive keyword matching is
  now UTF-16 code-unit exact, matching highlight.js's JavaScript object
  lookup. Previously, Swift `String` canonical equivalence let an NFC
  keyword match NFD input — an accidental divergence from upstream. All
  bundled grammars use ASCII keywords and are unaffected.
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

## 0.1.1 — 2026-07-10

- Fixed: hoisted the Swift grammar's long `[Mode] + [Mode] + …`
  concatenation chains into explicitly-typed locals, keeping the
  expressions under the compiler's type-check limit on the slower CI
  toolchains (iOS/watchOS and DocC jobs). Pure refactor; token output
  is unchanged.

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
