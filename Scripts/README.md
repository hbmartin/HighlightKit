# Differential-testing scripts

`difftest.py` and `tokenize-batch.mjs` compare this engine's token stream
against the highlight.js reference (see [`Docs/FIDELITY.md`](../Docs/FIDELITY.md)).

Setup (one-time): check out the pinned highlight.js 11.11.1 source (commit
`08cb242e7d4aee787114eb04cc7ab18314d82f92`), build its official Node target,
then point `HIGHLIGHTJS_DIR` at that repository root. The runner loads the
generated CommonJS modules under `build/lib`; it never patches the upstream
ESM source. No personal or temporary paths are embedded in the scripts.

```sh
git clone --branch 11.11.1 --depth 1 \
  https://github.com/highlightjs/highlight.js.git /path/to/highlight.js
(cd /path/to/highlight.js && npm ci && npm run build)
swift build -c release
HIGHLIGHTJS_DIR=/path/to/highlight.js \
  python3 Scripts/difftest.py <language> [count] [seed]
```

`count` is the number of generated fuzz cases; fixed edge cases and mutations
of checked-in fixtures are added to it. `seed` makes generation deterministic.
You can pass `--reference /path/to/highlight.js` and
`--swift-binary /path/to/highlight-bench` instead of the environment defaults.

The default mutation set is ASCII, matching highlight.js grammar regex
semantics. Pass `--unicode` to probe and report the documented ICU versus
JavaScript `\w`/`\b` differences; divergences still produce a nonzero exit.
Reference-process failures and result-count mismatches are also hard failures,
so a broken reference setup cannot be mistaken for a clean run.

`tokenize-batch.mjs` (reference) and `highlight-bench --tokens-batch`
(Swift) both read JSONL `{"lang","code"}` on stdin and emit
`{"tokens","relevance"}` per line. The reference runner also reports
`referenceEOFUnitsClipped`: highlight.js can append one synthetic newline to
an unterminated zero-width token at EOF, but an `NSRange` into the original
Swift string may not exceed its UTF-16 length. The runner clips only that
single, terminal, known unit and rejects every other out-of-range token;
`difftest.py` validates both engines' complete token streams and prints the
normalization count instead of hiding it.

For a reproducible result, record the highlight.js commit, language,
count, seed, HighlightKit commit, OS, and Swift toolchain. Reference errors
are failures rather than silently skipped inputs.
