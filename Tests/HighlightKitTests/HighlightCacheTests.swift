import Dispatch
import Foundation
import Synchronization
import Testing
@testable import HighlightKit

@Suite("Bounded highlight cache")
struct HighlightCacheTests {
    private let key = HighlightCacheKey(namespace: "test", value: "blob-1")

    private func makeCache(countLimit: Int? = nil) -> HighlightCache {
        HighlightCache(
            costLimit: 1_000_000,
            countLimit: countLimit,
            automaticallyPurgesOnMemoryPressure: false
        )
    }

    @Test func aliasesShareCanonicalEntriesAndBudgetsConsumeCompleteHits() async throws {
        let cache = makeCache()
        let code = "const answer = 42"
        let full = try await Highlighter.shared.highlight(
            code,
            selection: .named("js"),
            cache: cache,
            cacheKey: key
        )
        let budgeted = try await Highlighter.shared.highlight(
            code,
            selection: .named("javascript"),
            budget: HighlightBudget(maximumTokens: 0),
            cache: cache,
            cacheKey: key
        )
        let warm = try await Highlighter.shared.highlight(
            code,
            selection: .named("javascript"),
            cache: cache,
            cacheKey: key
        )

        #expect(!full.tokens.isEmpty)
        #expect(budgeted.tokens.isEmpty)
        #expect(budgeted.omittedTokenCount == full.tokens.count)
        #expect(warm.tokens == full.tokens)
        let metrics = await cache.metrics
        #expect(metrics.misses == 1)
        #expect(metrics.hits == 2)
        #expect(metrics.count == 1)
    }

    @Test func budgetedMissBypassesInsertion() async throws {
        let cache = makeCache()
        _ = try await Highlighter.shared.highlight(
            "let x = 1",
            selection: .named("swift"),
            budget: HighlightBudget(maximumTokens: 0),
            cache: cache,
            cacheKey: key
        )
        var metrics = await cache.metrics
        #expect(metrics.bypasses == 1)
        #expect(metrics.count == 0)

        _ = try await Highlighter.shared.highlight(
            "let x = 1",
            selection: .named("swift"),
            cache: cache,
            cacheKey: key
        )
        metrics = await cache.metrics
        #expect(metrics.misses == 2)
        #expect(metrics.count == 1)
    }

    @Test func effectiveKeyIncludesCallerOptionsLengthContinuationAndRegistry() async throws {
        let cache = makeCache()
        let highlighter = Highlighter()
        let first = try await highlighter.highlight(
            "/* open",
            selection: .named("swift"),
            cache: cache,
            cacheKey: key
        )
        _ = try await highlighter.highlight(
            "/* open",
            selection: .named("swift"),
            options: HighlightOptions(ignoreIllegals: false),
            cache: cache,
            cacheKey: key
        )
        _ = try await highlighter.highlight(
            "different length",
            selection: .named("swift"),
            cache: cache,
            cacheKey: key
        )
        _ = try await highlighter.highlight(
            "/* open",
            selection: .named("swift"),
            continuation: first.continuation,
            cache: cache,
            cacheKey: key
        )
        _ = try await Highlighter().highlight(
            "/* open",
            selection: .named("swift"),
            cache: cache,
            cacheKey: key
        )

        let metrics = await cache.metrics
        #expect(metrics.misses == 5)
        #expect(metrics.count == 5)
    }

    @Test func grammarReplacementAndNegativeCacheUseRegistryRevision() async throws {
        let highlighter = Highlighter(languages: [])
        let cache = makeCache()

        for expectedHit in [false, true] {
            do {
                _ = try await highlighter.highlight(
                    "word",
                    selection: .named("newlang"),
                    cache: cache,
                    cacheKey: key
                )
                Issue.record("unknown language unexpectedly succeeded")
            } catch HighlightError.unknownLanguage(let name) {
                #expect(name == "newlang")
            }
            let metrics = await cache.metrics
            #expect((metrics.negativeHits > 0) == expectedHit)
        }

        highlighter.register(simpleLanguage(name: "newlang", scope: "keyword"))
        let result = try await highlighter.highlight(
            "word",
            selection: .named("newlang"),
            cache: cache,
            cacheKey: key
        )
        #expect(result.tokens.first?.scope == "keyword")

        highlighter.register(simpleLanguage(name: "newlang", scope: "string"))
        let replacement = try await highlighter.highlight(
            "word",
            selection: .named("newlang"),
            cache: cache,
            cacheKey: key
        )
        #expect(replacement.tokens.first?.scope == "string")
    }

    @Test func lruEvictionIsDeterministicAndPressurePurges() async throws {
        let cache = makeCache(countLimit: 2)
        let highlighter = Highlighter.shared
        func request(_ value: String) async throws {
            _ = try await highlighter.highlight(
                "let x = 1",
                selection: .named("swift"),
                cache: cache,
                cacheKey: HighlightCacheKey(namespace: "lru", value: value)
            )
        }

        try await request("a")
        try await request("b")
        try await request("a")
        try await request("c")
        try await request("b")
        var metrics = await cache.metrics
        #expect(metrics.hits == 1)
        #expect(metrics.evictions == 2)
        #expect(metrics.count == 2)
        #expect(metrics.currentCost > 0)

        await cache.handleMemoryPressure()
        metrics = await cache.metrics
        #expect(metrics.purges == 1)
        #expect(metrics.count == 0)
        #expect(metrics.currentCost == 0)
    }

    @Test func unknownLanguageNegativeEntriesUseOnlyNameAndRegistryRevision() async throws {
        let highlighter = Highlighter(languages: [])
        let cache = makeCache()
        let continuation = try await Highlighter.shared.highlight(
            "/* open",
            selection: .named("swift")
        ).continuation
        let requests: [(String, String, String, HighlightOptions, Continuation?)] = [
            ("a", "nope", "first", HighlightOptions(), nil),
            (
                "a much longer source text",
                "NOPE",
                "second",
                HighlightOptions(ignoreIllegals: false),
                continuation
            ),
            ("different source", "nope", "third", HighlightOptions(), nil),
        ]
        for (code, requested, caller, options, continuation) in requests {
            do {
                _ = try await highlighter.highlight(
                    code,
                    selection: .named(requested),
                    options: options,
                    continuation: continuation,
                    cache: cache,
                    cacheKey: HighlightCacheKey(namespace: "negative", value: caller)
                )
                Issue.record("unknown language unexpectedly succeeded")
            } catch HighlightError.unknownLanguage(let name) {
                #expect(name.lowercased() == "nope")
            }
        }
        let metrics = await cache.metrics
        #expect(metrics.count == 1)
        #expect(metrics.currentCost == 1)
        #expect(metrics.misses == 1)
        #expect(metrics.negativeHits == 2)
        #expect(metrics.insertions == 1)
    }

    @Test func concurrentRequestsUseOneProducerAndCancelWaitersIndependently() async throws {
        let buildStarted = Mutex(false)
        let releaseBuild = DispatchSemaphore(value: 0)
        let descriptor = LanguageDescriptor(name: "slow", aliases: ["sl"]) {
            buildStarted.withLock { $0 = true }
            releaseBuild.wait()
            return LanguageDefinition(
                name: "slow",
                root: Mode(contains: [Mode(scope: "keyword", begin: "word")])
            )
        }
        let highlighter = Highlighter(languages: [descriptor])
        let cache = makeCache()
        let first = Task {
            try await highlighter.highlight(
                "word",
                selection: .named("slow"),
                cache: cache,
                cacheKey: key
            )
        }
        while !buildStarted.withLock({ $0 }) {
            await Task.yield()
        }
        let second = Task {
            try await highlighter.highlight(
                "word",
                selection: .named("sl"),
                cache: cache,
                cacheKey: key
            )
        }
        try await Task.sleep(for: .milliseconds(20))
        first.cancel()
        releaseBuild.signal()

        do {
            _ = try await first.value
            Issue.record("cancelled waiter unexpectedly succeeded")
        } catch is CancellationError {}
        let result = try await second.value
        #expect(result.tokens.first?.scope == "keyword")
        let metrics = await cache.metrics
        #expect(metrics.coalescedRequests == 1)
        #expect(metrics.insertions == 1)
    }

    @Test func cancellingEveryWaiterCancelsProducerAndStoresNothing() async throws {
        let buildStarted = Mutex(false)
        let releaseBuild = DispatchSemaphore(value: 0)
        let descriptor = LanguageDescriptor(name: "abandoned") {
            buildStarted.withLock { $0 = true }
            releaseBuild.wait()
            return LanguageDefinition(
                name: "abandoned",
                root: Mode(contains: [Mode(scope: "keyword", begin: "word")])
            )
        }
        let highlighter = Highlighter(languages: [descriptor])
        let cache = makeCache()
        let first = Task {
            try await highlighter.highlight(
                "word",
                selection: .named("abandoned"),
                cache: cache,
                cacheKey: key
            )
        }
        while !buildStarted.withLock({ $0 }) { await Task.yield() }
        let second = Task {
            try await highlighter.highlight(
                "word",
                selection: .named("abandoned"),
                cache: cache,
                cacheKey: key
            )
        }
        while await cache.metrics.coalescedRequests == 0 { await Task.yield() }

        first.cancel()
        second.cancel()
        for task in [first, second] {
            do {
                _ = try await task.value
                Issue.record("cancelled waiter unexpectedly succeeded")
            } catch is CancellationError {}
        }
        releaseBuild.signal()
        await Task.yield()

        let metrics = await cache.metrics
        #expect(metrics.count == 0)
        #expect(metrics.insertions == 0)
    }

    @Test func failedProducersAreNotCached() async {
        let invalid = LanguageDescriptor(name: "invalid") {
            LanguageDefinition(
                name: "invalid",
                root: Mode(contains: [Mode(begin: "(")])
            )
        }
        let highlighter = Highlighter(languages: [invalid])
        let cache = makeCache()
        for _ in 0..<2 {
            do {
                _ = try await highlighter.highlight(
                    "word",
                    selection: .named("invalid"),
                    cache: cache,
                    cacheKey: key
                )
                Issue.record("invalid grammar unexpectedly succeeded")
            } catch {}
        }
        let metrics = await cache.metrics
        #expect(metrics.misses == 2)
        #expect(metrics.count == 0)
    }

    private func simpleLanguage(name: String, scope: String) -> LanguageDescriptor {
        LanguageDescriptor(name: name) {
            LanguageDefinition(
                name: name,
                root: Mode(contains: [Mode(scope: .name(scope), begin: "word")])
            )
        }
    }
}
