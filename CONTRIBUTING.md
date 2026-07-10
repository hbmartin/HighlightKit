# Contributing to HighlightKit

Thanks for helping build native syntax highlighting for Apple platforms.

## Development setup

```sh
git clone https://github.com/PhraseHQ/HighlightKit.git && cd HighlightKit
swift build          # Xcode 16.3+ / Swift 6.1+
swift test           # all tests must stay green
```

Concurrency and coverage are separate instrumented runs:

```sh
swift test --sanitize=thread \
  --filter 'LanguageRegistryTests|IncrementalTests|StressTests|CoreCoverageCompletionTests'
swift test --enable-code-coverage
swift test --show-codecov-path
```

## The correctness bar

HighlightKit is verified against highlight.js itself, and PRs are held to
that:

- **375 token-exact fidelity fixtures** (`Tests/HighlightKitTests/Fixtures/`)
  assert identical token streams to the reference highlight.js on every
  `swift test`. A change that shifts any token is either a bug or needs
  regenerated fixtures with justification.
- **Differential suites** pin hand-written fast paths to live ICU at
  runtime: every matcher prefilter (arrow functions, number literals,
  identifier heads, keyword alternations) is fuzzed against raw
  `NSRegularExpression` enumeration with seeded, deterministic corpora.
  If you optimize a matching path, add the same kind of differential test.
- Faithful-port rule: highlight.js behavior wins, including quirks.
  Deliberate divergences must be pinned by an explicit test.

## Performance

Performance changes must come with numbers. Use the bench target:

```sh
swift build -c release
.build/release/highlight-bench 5 javascript            # throughput
.build/release/highlight-bench 5 javascript --incremental  # per-line latency
.build/release/highlight-bench --auto 10               # language detection
.build/release/highlight-bench --render 20 swift       # NSAttributedString
```

Freeze baseline and candidate executables from the same
`swift build -c release` configuration. Warm each scenario, interleave
process-level A/B order in the same thermal batch, include an unaffected
negative-control workload, and verify token counts. Report absolute medians,
paired relative effects, confidence intervals, machine/OS/toolchain, and exact
commands; retain the raw machine-readable samples and statistics script. An
optimization that cannot demonstrate a real-workload win is
reverted; an interval crossing zero is neutral. Never compare a testable binary
emitted by `swift test` with a production binary emitted by `swift build`.

Record every adopted and rejected experiment in
[`Docs/PERFORMANCE.md`](Docs/PERFORMANCE.md). Several "obviously faster"
designs measured slower; keeping the rejected results prevents the same work
from being repeated.

## Adding a language

Grammars live in `Sources/HighlightKit/Languages/`, one file per language,
ported from the corresponding highlight.js 11.11.1 grammar. Register a new
descriptor in `LanguageCatalog`, compare it with the pinned source through
`Scripts/difftest.py`, add reviewed fixtures, and make the fidelity suite pass.
The full workflow and fixture-provenance requirements are in
[`Docs/PORTING.md`](Docs/PORTING.md).

## Commit style

`feat:` / `fix:` / `perf:` / `test:` / `refactor:` / `chore:` prefixes;
imperative subject; body explains the why and includes measured numbers
for perf changes.
