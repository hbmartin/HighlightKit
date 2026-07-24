# Migrating from HighlightKit 0.2.0 to 0.3.0

HighlightKit 0.3.0, released July 24, 2026, makes language intent explicit and
turns previously silent failures into errors. It also adds repository-aware
language resolution, bounded rendering and caching, and an incremental
document actor.

The package requirements are unchanged: Swift 6.1 and iOS 18, macOS 15,
tvOS 18, watchOS 11, or visionOS 2. Existing themes, token consumers,
continuations, and custom grammars remain usable after the highlighting call
sites are updated. `HighlightResult.attributedString(for:theme:)` also keeps
the same signature.

This guide first covers the source-breaking changes required to compile, then
the behavioral choices that should be reviewed, and finally the optional 0.3
APIs.

## Migration at a glance

1. Update the Swift Package Manager dependency to `0.3.0`.
2. Replace `highlight(_:as:...)` with the throwing
   `highlight(_:selection:options:budget:continuation:)` API.
3. Replace `highlightAuto` with `.automatic`; move `subset` into
   `HighlightOptions.automaticSubset`.
4. Replace the nullable `language:` argument of the one-call renderer with an
   explicit `.named`, `.automatic`, or `.plain` selection.
5. Decide how each call site handles unknown languages, invalid custom
   grammars, and cancellation. Do not mechanically suppress every error unless
   plain-text fallback is the intended product behavior.
6. Run the tests with unknown language names, cancellation, non-BMP source,
   and any automatic-detection subsets used by the application.

For an exact package requirement:

```swift
dependencies: [
    .package(
        url: "https://github.com/PhraseHQ/HighlightKit.git",
        exact: "0.3.0"
    )
]
```

## Required source changes

| 0.2.0 | 0.3.0 |
|---|---|
| `highlight(…, as: name)` | `try highlight(…, selection: .named(name))` |
| `ignoreIllegals:` argument | `HighlightOptions(ignoreIllegals:)` |
| `highlightAuto(…)` | `try highlight(…, selection: .automatic)` |
| `subset:` argument | `HighlightOptions(automaticSubset:)` |
| `await highlightAuto(…)` | `try await highlight(…, selection: .automatic)` |
| `language: name` | `selection: .named(name)` |
| `language: nil` | `selection: .automatic` |
| No plain request | `selection: .plain` |

### Named highlighting

The language name or alias is now wrapped in `LanguageSelection.named`, and
the operation throws.

```swift
// 0.2.0
let result = highlighter.highlight(
    code,
    as: languageName,
    ignoreIllegals: false,
    continuation: previousContinuation
)

// 0.3.0
let result = try highlighter.highlight(
    code,
    selection: .named(languageName),
    options: HighlightOptions(ignoreIllegals: false),
    continuation: previousContinuation
)
```

Names remain case-insensitive, and aliases still resolve to the canonical
language name reported by `result.language`. The difference is that an unknown
name no longer returns an unhighlighted result.

### Automatic detection

Synchronous and asynchronous detection now use the same request shape.

```swift
// 0.2.0: synchronous
let result = highlighter.highlightAuto(
    code,
    subset: ["swift", "objectivec"]
)

// 0.3.0: synchronous
let result = try highlighter.highlight(
    code,
    selection: .automatic,
    options: HighlightOptions(
        automaticSubset: ["swift", "objectivec"]
    )
)
```

Use the asynchronous overload when the caller can suspend. It is
processor-bounded and cooperatively cancellable:

```swift
let result = try await highlighter.highlight(
    code,
    selection: .automatic,
    options: HighlightOptions(automaticSubset: candidateNames)
)
```

Unknown entries in an automatic subset are skipped. If no registered
candidate produces relevance, plain text wins and `result.language` is `nil`;
this is not an error. If an empty or fully unknown subset was accidental,
validate it in the application before making the request.

### One-call attributed strings

The old nullable language argument combined two different operations. Replace
it with the intended selection and add `try` or `try await`.

```swift
// 0.2.0: a name highlighted; nil triggered automatic detection
let text = highlighter.attributedString(
    for: code,
    language: languageName,
    theme: .xcode
)

// 0.3.0: named
let text = try highlighter.attributedString(
    for: code,
    selection: .named(languageName),
    theme: .xcode
)

// 0.3.0: automatic
let detectedText = try await highlighter.attributedString(
    for: code,
    selection: .automatic,
    theme: .xcode
)

// 0.3.0: intentionally unhighlighted, but with the theme's base font/color
let plainText = try highlighter.attributedString(
    for: code,
    selection: .plain,
    theme: .xcode
)
```

Code that already separates parsing from rendering can keep calling:

```swift
let text = result.attributedString(for: code, theme: .xcode)
```

That convenience remains nonthrowing. In 0.3 it delegates to
`HighlightRenderer` and clips syntax overlays to the shared UTF-16 prefix if a
result is accidentally paired with text of a different length.

## Replace silent fallback with an explicit policy

In 0.2.0, named highlighting caught all lookup and grammar-compilation errors
and returned a result with no tokens. In 0.3.0, named highlighting may throw:

- `HighlightError.unknownLanguage` for an unregistered name or alias;
- `HighlightError.invalidRegex` for an invalid regular expression in a custom
  grammar;
- `HighlightError.invalidGrammar` for another grammar-compilation failure; or
- `CancellationError` from the asynchronous overload.

The new behavior prevents a typo such as `"javasript"` from looking like a
successful plain-text highlight. Prefer surfacing configuration errors during
development and choosing fallback only at a user-input boundary.

For example, this adapter preserves plain output for an unknown user-supplied
name while allowing invalid grammars and cancellation to keep propagating:

```swift
func highlightUserInput(
    _ code: String,
    languageName: String,
    using highlighter: Highlighter
) throws -> HighlightResult {
    do {
        return try highlighter.highlight(
            code,
            selection: .named(languageName)
        )
    } catch HighlightError.unknownLanguage {
        return try highlighter.highlight(code, selection: .plain)
    }
}
```

At an attributed-string UI boundary, a fully nonthrowing fallback can be made
equally explicit:

```swift
func renderedCode(
    _ code: String,
    languageName: String,
    using highlighter: Highlighter
) -> NSAttributedString {
    do {
        return try highlighter.attributedString(
            for: code,
            selection: .named(languageName),
            theme: .github
        )
    } catch {
        return NSAttributedString(string: code)
    }
}
```

Use `.plain` when no highlighting is intentional. Reserve error recovery for
failed requests so telemetry and tests can distinguish the two cases.

### Cancellation changed

The 0.2 asynchronous automatic detector could return a ranking over the
candidates that completed before cancellation. The 0.3 asynchronous overload
never returns a partial result: cancellation throws `CancellationError` for
named and automatic requests.

```swift
do {
    let result = try await highlighter.highlight(
        code,
        selection: .automatic
    )
    display(result)
} catch is CancellationError {
    // The request was superseded. Keep or clear the previous UI as intended.
} catch {
    report(error)
}
```

Do not interpret cancellation as plain text, and do not publish a result after
the task has been superseded.

## Options, budgets, and result metadata

`HighlightOptions` contains parsing semantics shared by the synchronous and
asynchronous APIs:

```swift
let options = HighlightOptions(
    ignoreIllegals: true,
    automaticSubset: ["swift", "objectivec"]
)
```

`automaticSubset` is used only with `.automatic`. `ignoreIllegals` has the
same meaning as the 0.2 argument: when `false`, illegal input returns a result
whose `illegal` property is `true` and whose tokens are empty.

`HighlightBudget` limits retained tokens without stopping the parser:

```swift
let result = try highlighter.highlight(
    code,
    selection: .named("swift"),
    budget: HighlightBudget(maximumTokens: 2_000)
)

if result.isTruncated {
    log("Omitted \(result.omittedTokenCount) syntax tokens")
}
```

The parser still processes the complete source, so `relevance` and
`continuation` are exact. A token budget bounds result size and downstream
work; it is not a parser time limit. `maximumTokens` must be nonnegative.

Every 0.3 result also reports:

- `sourceLength`: the source's UTF-16 length, matching `NSRange` and TextKit
  coordinates;
- `omittedTokenCount`: the number of tokens removed by a budget; and
- `isTruncated`: whether any tokens were omitted.

Do not compare `sourceLength` to `String.count`. For example, `"a😀"` has a
`sourceLength` of 3 UTF-16 code units.

## Repository-aware language selection

Use the new resolver when the application knows a repository path,
interpreter, shebang, or caller override. Resolve once, then pass the returned
selection to highlighting:

```swift
let selection = try await highlighter.resolveLanguage(
    for: code,
    path: repositoryRelativePath,
    interpreter: executableName,
    override: userOverride
)

let result = try await highlighter.highlight(
    code,
    selection: selection
)
```

Resolution uses this precedence:

1. caller override;
2. exact filename;
3. explicit interpreter, or the source shebang when no interpreter is passed;
4. longest matching file extension; and
5. `.plain` when no metadata matches.

A `.named` override is canonicalized and throws when unknown. An `.automatic`
override requests unrestricted content detection. Ambiguous metadata, such as
`.h` or `.m`, restricts content detection to the matched candidates and falls
back to `.plain` when they all have zero relevance.

`highlighter.languages` exposes the registered `[LanguageInfo]`, while
`highlighter.language(named:)` looks up a canonical name or alias. Each
`LanguageInfo` contains normalized extensions, exact filenames, and
interpreters. See [LANGUAGE_RESOLUTION.md](LANGUAGE_RESOLUTION.md) for shebang
and metadata details.

## Optional: overlay existing attributed text

The 0.2 attributed-string conveniences create a new string and apply a base
font and foreground color. Keep using the 0.3 convenience when that is the
desired behavior.

Use `HighlightRenderer` when syntax should be composed with attributes already
owned by the application, such as links, paragraph styles, diff backgrounds,
or selection markers:

```swift
let result = try highlighter.highlight(
    code,
    selection: .named("swift")
)

let renderer = HighlightRenderer(theme: .githubDark)
let summary = try renderer.apply(
    result,
    to: textStorage,
    options: HighlightRenderOptions(
        appliesForegroundColors: true,
        appliesFontTraits: true,
        maximumRenderedRuns: 5_000
    )
)

if summary.isTruncated {
    log("Omitted \(summary.omittedRuns) rendered runs")
}
```

The renderer changes only requested foreground colors and font traits. It does
not replace links, backgrounds, paragraph styles, or unrelated attributes.
Reuse a renderer for a theme so its resolved styles and font variants are
reused as well.

For a diff hunk or visible slice, map equal-length UTF-16 ranges from the
highlighted source into destination storage:

```swift
let mapping = HighlightRangeMapping(
    sourceRange: sourceRange,
    destinationRange: destinationRange
)
try renderer.apply(result, to: textStorage, mappings: [mapping])
```

Explicit mappings throw `HighlightRenderingError.invalidRangeMapping` if a
range is negative, lengths differ, or either range exceeds its source. Without
explicit mappings, rendering clips to the shared prefix of the result and
destination. See [RENDERING.md](RENDERING.md).

Token and rendering budgets solve different problems. `HighlightBudget` caps
stored syntax tokens. `maximumRenderedRuns` caps actual attributed-string
mutations after range mapping, style coalescing, and intersections with
existing font runs.

## Optional: cache complete token results

There is no implicit result cache in `Highlighter.shared`. Applications with a
stable content identity can create an explicit cache and use the asynchronous
highlight API:

```swift
let cache = HighlightCache(
    costLimit: 16 * 1024 * 1024,
    countLimit: 2_000
)

let result = try await highlighter.highlight(
    code,
    selection: .named("swift"),
    cache: cache,
    cacheKey: HighlightCacheKey(
        namespace: "git-blob",
        value: blobObjectID
    )
)
```

Both `cache` and `cacheKey` are required to use caching. The key is an opaque
identity supplied by the caller; the cache does not hash or retain the source
text. Its effective request key includes the highlighter registry and
revision, canonical selection, options, UTF-16 source length, and continuation
identity. It does not include source contents, the theme, or the renderer.

Never reuse a content identity for different source with the same UTF-16
length. Namespace identities from different domains, for example `git-blob`,
`database-row`, or `generated-message`.

The cache coalesces identical in-flight work and isolates waiter cancellation.
Failed, cancelled, and token-truncated results are not inserted. A budgeted
request can consume an existing complete result, but a budgeted miss bypasses
insertion. See [CACHING.md](CACHING.md) for eviction, metrics, purge, and
memory-pressure behavior.

## Optional: replace manual editor propagation

Existing continuation loops still compile after their highlight calls gain
`try`. A direct migration looks like this:

```swift
var continuation: Continuation?
for line in lines {
    let result = try highlighter.highlight(
        line,
        selection: .named(languageName),
        continuation: continuation
    )
    continuation = result.continuation
}
```

For an editor or visible-range consumer, `HighlightedDocument` can own the
text, per-line tokens, continuation checkpoints, and edit propagation:

```swift
let document = try await HighlightedDocument(
    text: source,
    highlighter: highlighter,
    selection: .named("swift")
)

let update = try await document.replaceCharacters(
    in: editedUTF16Range,
    with: replacement
)

let visible = try await document.snapshot(
    in: visibleUTF16Range,
    maximumTokens: 500
)
```

Edits and ranges use UTF-16 coordinates. Each edit is transactional; a failed
or cancelled edit leaves the previous state intact. Concurrent edits are
committed in arrival order. Snapshot tokens are clipped to the requested range
and rebased to the snapshot text.

An `.automatic` document detects once from the complete initial text and pins
that canonical language for later edits. Construct a new document when an edit
should trigger language detection again. Line-isolated highlighting retains
the same cross-line regex limitations as manual 0.2 continuation loops; use
whole-buffer highlighting when token-exact context across line boundaries is
required. See [HIGHLIGHTED_DOCUMENT.md](HIGHLIGHTED_DOCUMENT.md) and the
[incremental fidelity notes](FIDELITY.md#incremental-line-by-line-highlighting).

## Custom grammars and language metadata

The existing `LanguageDescriptor` initializer remains source-compatible
because its new `metadata` argument defaults to `nil`:

```swift
let language = LanguageDescriptor(
    name: "mydsl",
    aliases: ["my-dsl"],
    metadata: LanguageMetadata(
        fileExtensions: ["mydsl", ".myd"],
        filenames: ["MyDSLfile", ".mydslrc"],
        interpreters: ["mydsl"]
    )
) {
    LanguageDefinition(name: "mydsl", root: rootMode)
}
```

Metadata is normalized case-insensitively; leading dots are removed from
extensions, interpreter paths are reduced to their executable name, empty
values are discarded, and duplicates are removed. Supplying metadata lets the
repository resolver select the custom grammar. Registration and lazy grammar
compilation otherwise work as in 0.2.

Invalid custom grammar compilation is now observable at named highlight call
sites. Add tests that force a cold compile and assert the expected
`HighlightError` rather than relying only on registration succeeding.

## Bundled language and detection changes

The bundled catalog grows from 65 to 71 grammars:

- Elixir (`elixir`, aliases `ex` and `exs`);
- Fish (`fish`);
- GraphQL (`graphql`, alias `gql`);
- Protocol Buffers (`protobuf`, alias `proto`);
- Terraform/HCL (`terraform`, aliases `tf` and `hcl`); and
- Zig (`zig`).

These languages are available by explicit name and repository metadata. Fish
is excluded from automatic detection, including an explicit automatic subset,
but can be selected by name, extension, or interpreter/shebang. The other new
candidates can change unrestricted automatic-detection rankings, so pin the
expected language and runner-up for representative application samples. Use
`automaticSubset` when the surrounding context already limits the possible
languages.

## Verification checklist

- The package resolves to 0.3.0 and all old `highlight(_:as:)`,
  `highlightAuto`, and nullable `language:` calls are gone from application
  code.
- Named calls use `try`; asynchronous calls use `try await` and handle
  `CancellationError` separately from real failures.
- Unknown user-supplied names have an intentional policy; typos in fixed
  application language names fail tests instead of silently rendering plain.
- Automatic subsets contain registered names or aliases and still choose the
  expected language after the catalog expansion.
- `ignoreIllegals` and automatic subsets moved into `HighlightOptions` without
  changing their intended values.
- Any token budget checks `isTruncated` or `omittedTokenCount` before assuming
  all tokens are present.
- Code that compares source and token ranges uses UTF-16 lengths and
  `NSRange`, not grapheme-cluster `String.count`.
- Cache identities cannot collide for different same-length content, and both
  the cache and cache key are passed only on asynchronous calls.
- Explicit renderer mappings are equal-length, in-bounds UTF-16 ranges; render
  budgets are tested with existing mixed-font attributed text.
- Incremental edit and snapshot ranges are valid UTF-16 boundaries, and
  automatic documents are recreated when language selection should change.

After the required call-site migration, the optional features can be adopted
independently. Repository resolution does not require caching; caching does
not require the overlay renderer; and `HighlightedDocument` is unnecessary
for consumers that continue to highlight complete blocks.
