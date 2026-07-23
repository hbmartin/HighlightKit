# Incremental documents

`HighlightedDocument` is an actor-isolated helper for editors and read-only
range consumers. It retains line tokens and continuation checkpoints (every 32
lines by default), preserves LF, CRLF, and CR terminators, and accepts edits in
UTF-16 coordinates.

```swift
let document = try await HighlightedDocument(
    text: source,
    selection: .named("swift")
)

try await document.replaceCharacters(in: editedRange, with: replacement)
let visible = try await document.snapshot(in: visibleRange, maximumTokens: 500)
```

An edit resumes from the preceding checkpoint. When both source text and
continuation state match at an unchanged suffix checkpoint, the remaining
line tokens and checkpoints are reused. Parsing is transactional: new state is
published only after the complete edit succeeds and passes its final
cancellation check.

Snapshot token ranges are clipped to the selected source range and rebased to
the returned snapshot text. This makes a visible-range snapshot directly
renderable without retaining or materializing attributed text for the rest of
the document.

Automatic selection runs once against the initial complete document and is
then fixed to the detected canonical language. Use repository resolution when
file metadata is available, and create a new document if an edit should cause
the language itself to be reconsidered.
