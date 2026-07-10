# Fidelity with highlight.js

This engine aims to reproduce highlight.js 11.11.1's token stream — the same
UTF-16 ranges, scope stacks, and relevance — subject to the documented ICU
Unicode boundary difference below. Two complementary methods verify it:

1. **Corpus fixtures** (`Tests/HighlightKitTests/Fixtures`, 375 cases): an
   upstream-derived corpus plus reviewed adversarial additions is run through
   the real pinned highlight.js source with a token-capturing emitter. The
   Swift port must match the generated expectations token-for-token, with
   relevance compared to a tolerance of 0.001.
   Run: `swift test --filter matchesReference`.
2. **Differential fuzzing**: seeded random and corpus-mutated inputs are
   tokenized by *both* engines and compared. This expands coverage beyond
   the fixed corpus; it is evidence, not an exhaustive proof.

## Differential fuzzing

The checked-in harness is `Scripts/difftest.py` plus
`Scripts/tokenize-batch.mjs`. It deliberately requires an external checkout
of the pinned highlight.js source rather than embedding a personal path. Tag
`11.11.1` resolves to commit `08cb242e7d4aee787114eb04cc7ab18314d82f92`:

```sh
git clone --branch 11.11.1 --depth 1 \
  https://github.com/highlightjs/highlight.js.git /path/to/highlight.js
(cd /path/to/highlight.js && npm ci && npm run build)
swift build -c release
HIGHLIGHTJS_DIR=/path/to/highlight.js \
  python3 Scripts/difftest.py javascript 200 1
```

- `Scripts/tokenize-batch.mjs` — reads JSONL `{lang, code}`, emits the reference
  token stream per line (grammars loaded once). It source-bounds the one known
  highlight.js synthetic EOF-newline case and reports every clipped unit.
- `highlight-bench --tokens-batch` — the Swift engine, same JSONL
  protocol and output shape.
- `Scripts/difftest.py <lang> [count] [seed]` — builds fuzz inputs (corpus +
  mutations + random), runs both, diffs, prints minimal repros.

Two real bugs were found this way and fixed (see git history):

- **EOF zero-width deadlock crash** — the issue-#2140 guard appended an
  out-of-bounds `NSRange` at end-of-input → `NSRangeException`.
- **`MATCH_NOTHING_RE` (`\b\B`) end deadlock** — `NSRegularExpression`
  reports `\b\B` at EOF via `enumerateMatches` but not via
  `firstMatch(.anchored)`; the disagreement spun the parse loop until
  the infinite-loop guard discarded all tokens (HTTP header bodies).

The 2026-07-10 all-language campaign found **0 comparable divergences across
28,750 default-campaign inputs over all 65 languages**. Generated mutations
inject only ASCII/NUL, while 160 corpus-derived inputs retain non-ASCII text.
The run normalized **106** synthetic reference EOF units (CSS 31, Less 30,
SCSS 23, Stylus 22); every Swift token was already source-bounded. Re-run it
with the HighlightKit and highlight.js commit IDs recorded whenever matcher or
grammar behavior changes; the fixed 375-case fixture suite remains the
per-commit CI guarantee.

## Known difference: Unicode `\d` / `\w` / `\b` (documented, not a bug)

The known divergence class appears when a non-ASCII character sits directly
against a syntax token — e.g. `20中0`, `3‍3`
(digit, zero-width-joiner, digit), or an identifier fused to a CJK
character with no separator. It is the fundamental, well-known difference
between the two regex engines:

| | JavaScript (highlight.js) | ICU (`NSRegularExpression`) |
|---|---|---|
| `\d` | ASCII `[0-9]` | `\p{Nd}` — all Unicode digits |
| `\w` | ASCII `[0-9A-Za-z_]` | Unicode word chars (letters, marks, `Join_Control`, …) |
| `\b` | boundary via ASCII `\w` | boundary via Unicode `\w` |

highlight.js grammars are authored against ASCII `\w`/`\b`. So `20中0`
tokenizes as two numbers under JS (because `中` is a non-word char that
breaks the number) but as one under ICU (because `中` *is* a word char,
so no `\b` boundary forms). `NSRegularExpression`/ICU exposes no flag to
force ASCII `\w`/`\b`.

In the recorded 6,000-input Unicode campaign, all 80 observed divergences
disappeared after the non-ASCII characters were stripped and both engines
were rerun. That result is consistent with this ICU-versus-JavaScript
semantic difference; it is not a proof that no other Unicode divergence can
exist.

**Decision: documented, not fixed.** The only exact fix is to rewrite
`\b`/`\B` in every pattern into ASCII-anchored lookarounds
(`(?<![0-9A-Za-z_])(?=[0-9A-Za-z_])…`). `\b` appears in nearly every
number and keyword rule, so this would impose a pervasive lookaround
cost on the hottest patterns — a real, measurable slowdown — to change
output only on rare Unicode-adjacent syntax (all 375 corpus fixtures and all
28,750 inputs in the recorded default campaign already match).
That trade fails the project's "high-performance, avoid unnecessary
cost" bar. If exact Unicode-adjacent fidelity is ever required, the
transform is well-defined and can be added as a compile-time pass behind
a flag; `Scripts/difftest.py --unicode` is the acceptance harness.

## Incremental (line-by-line) highlighting

Whole-string highlighting is exact (above). The `Continuation` API also
supports resuming a highlight line-by-line. It carries the **complete**
resumable state — mode stack, embedded sub-language continuations,
heredoc/`endSameAsBegin` callback data, and keyword-relevance counts — so
state that spans lines (open comments, heredoc bodies, embedded CSS/JS)
resumes correctly (`IncrementalTests`).

What it *cannot* carry is regex **context across a line boundary**: a line
highlighted in isolation cannot see the preceding or following text, so
`^`/`$`/`\b`/lookaround at a line edge and multi-line lookahead (e.g. a
`(…) =>` arrow function whose `=>` is on a later line) can make a
line-by-line pass differ from whole-string. In the recorded strict
line-isolation audit, about 11% of corpus files differed somewhere from
whole-input output; the reviewed mismatches involved cross-line
`^`/`$`/`\b`/lookaround context. Continuation-state regressions are tested
separately in `IncrementalTests`.

**Guidance:** for fixture-level exactness, highlight the whole block in one
call. Use the `Continuation` line path only when whole-block
re-highlight is too slow and minor line-edge differences are acceptable.
