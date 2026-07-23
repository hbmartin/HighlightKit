# Result caching

`HighlightCache` is an explicit actor-owned LRU cache for completed,
theme-independent `HighlightResult` values. `Highlighter.shared` has no hidden
cache. A caller supplies both its cache and a namespaced content identity:

```swift
let cache = HighlightCache(costLimit: 16 * 1024 * 1024, countLimit: 2_000)
let key = HighlightCacheKey(namespace: "git-blob", value: blobOID)
let result = try await highlighter.highlight(
    source,
    selection: .named("swift"),
    cache: cache,
    cacheKey: key
)
```

The effective key also contains the highlighter registry identity and revision,
canonical language (or ordered automatic subset), parser options, UTF-16 source
length, and initial continuation identity. It deliberately excludes source
contents, themes, fonts, and renderers. The caller is responsible for ensuring
that a content identity is not reused for different same-length source text.

The cache coalesces identical in-flight work. Cancelling a waiter stops only
that waiter's request; the producer is cancelled when no waiter remains.
Cancelled, failed, and token-truncated results are never inserted. A budgeted
request may consume a complete hit, but a miss bypasses insertion.

`metrics` reports hits, misses, coalesced requests, negative hits, bypasses,
insertions, evictions, purges, count, and current cost; cost is tracked
incrementally, so reading metrics never rescans the table. `purge()` is always
available; on Apple platforms caches also purge automatically on dispatch
memory-pressure events. Other platforms can forward their host lifecycle
notification to `handleMemoryPressure()`.
