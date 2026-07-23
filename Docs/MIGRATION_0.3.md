# Migrating to the repository-aware API

The next HighlightKit release intentionally removes nullable-language and
silent-fallback entry points. Language intent is now explicit and errors are
observable.

## Selection and errors

```swift
// Before
let named = highlighter.highlight(code, as: "swift")
let detected = await highlighter.highlightAuto(code)
let rendered = highlighter.attributedString(for: code, language: nil)

// Now
let named = try highlighter.highlight(code, selection: .named("swift"))
let detected = try await highlighter.highlight(code, selection: .automatic)
let plain = try highlighter.highlight(code, selection: .plain)
let rendered = try highlighter.attributedString(
    for: code,
    selection: .automatic
)
```

Aliases resolve to canonical language names. An unknown named language throws
`HighlightError.unknownLanguage`; task cancellation throws
`CancellationError`. Neither condition is converted to plain output. `.plain`
is the only intentional no-highlighting selection.

`HighlightOptions` carries parser semantics. `HighlightBudget` caps emitted
tokens while the parser still computes exact relevance and continuation state.
The result reports `sourceLength`, `omittedTokenCount`, and `isTruncated`.

## Repository resolution

Use `resolveLanguage(for:path:interpreter:override:)` before highlighting when
file identity is available. Resolution applies caller overrides, exact
filenames, interpreters/shebangs, and longest extensions in that order. It
uses candidate-restricted content detection for ambiguous `.h` and `.m`
files. See [LANGUAGE_RESOLUTION.md](LANGUAGE_RESOLUTION.md).

## Rendering overlays

Use one reusable `HighlightRenderer` to apply syntax colors and/or font traits
to caller-owned `NSMutableAttributedString` or `NSTextStorage`. Existing links,
backgrounds, paragraphs, and other application attributes remain intact.
`HighlightRangeMapping` handles selected and rebased UTF-16 ranges, while
`maximumRenderedRuns` bounds downstream TextKit complexity. See
[RENDERING.md](RENDERING.md).

## Explicit caching and documents

`Highlighter.shared` does not cache results. Pass an application-owned
`HighlightCache` and namespaced `HighlightCacheKey` to the async API when a
stable content identity is available. Cached tokens can be rendered repeatedly
with different themes and fonts. See [CACHING.md](CACHING.md).

For editable or visible-range consumers, `HighlightedDocument` owns per-line
tokens and continuation checkpoints, applies UTF-16 edits transactionally,
and exposes capped range snapshots. See
[HIGHLIGHTED_DOCUMENT.md](HIGHLIGHTED_DOCUMENT.md).
