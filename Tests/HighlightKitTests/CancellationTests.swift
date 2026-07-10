import Foundation
import Synchronization
import Testing

@testable import HighlightKit

@Suite("Cooperative cancellation")
struct CancellationTests {
    private func rule(_ pattern: String, slot: Int = 0) throws -> CompiledRule {
        try CompiledRule(
            pattern: pattern,
            kind: .illegal,
            options: [],
            language: "cancellation",
            slot: slot
        )
    }

    @Test func parserChecksCancellationAroundUTF16Materialization() throws {
        let descriptor = LanguageDescriptor(name: "materialization-cancellation") {
            LanguageDefinition(name: "materialization-cancellation", root: Mode())
        }
        let registry = LanguageRegistry(languages: [descriptor])
        let language = try registry.compiledLanguage(named: descriptor.name)

        for cancelAt in 1...2 {
            let calls = Mutex(0)
            let engine = HighlightEngine(
                registry: registry,
                cancellationProbe: {
                    calls.withLock { count in
                        count += 1
                        return count == cancelAt
                    }
                }
            )
            #expect(throws: CancellationError.self) {
                _ = try engine.highlight(
                    String(repeating: "a", count: 16_384) as NSString,
                    language: language,
                    ignoreIllegals: true
                )
            }
            #expect(calls.withLock { $0 } == cancelAt)
        }
    }

    @Test func keywordProgressCancellationIsSticky() throws {
        let descriptor = LanguageDescriptor(name: "keyword-cancellation") {
            LanguageDefinition(
                name: "keyword-cancellation",
                root: Mode(keywords: "keyword")
            )
        }
        let registry = LanguageRegistry(languages: [descriptor])
        let language = try registry.compiledLanguage(named: descriptor.name)
        let calls = Mutex(0)
        let engine = HighlightEngine(
            registry: registry,
            cancellationProbe: {
                calls.withLock { count in
                    count += 1
                    // 1: highlight entry; 2: after NSString materialization;
                    // 3: execute entry; 4: matcher exhausted. The fifth
                    // probe is therefore inside the keyword ICU progress
                    // callback. Keep it transient to prove the run retains
                    // the observation instead of relying on a sticky probe.
                    return count == 5
                }
            }
        )

        #expect(throws: CancellationError.self) {
            _ = try engine.highlight(
                String(
                    repeating: "a",
                    count: RuleMatchCache.cancellationProgressMinimumLength
                ) as NSString,
                language: language,
                ignoreIllegals: true
            )
        }
        // Exact count excludes the former false positive where the third
        // probe cancelled at `execute()` entry before keyword enumeration.
        #expect(calls.withLock { $0 } == 5)
    }

    @Test func oneOffProgressCancellationIsSticky() throws {
        let source = String(
            repeating: "a",
            count: RuleMatchCache.cancellationProgressMinimumLength
        )
        let state = Mutex((armed: false, calls: 0))
        let cache = RuleMatchCache(
            slotCount: 1,
            units: Array(source.utf16),
            cancellationProbe: {
                state.withLock { state in
                    guard state.armed else { return false }
                    state.calls += 1
                    return state.calls == 1
                }
            }
        )
        let rule = try rule("z")

        // Establish a cached sequence beginning at 1. Querying back at 0
        // must use the rare one-off overlap/non-monotonic search path.
        #expect(
            cache.firstMatch(
                for: rule,
                in: source,
                length: source.utf16.count,
                from: 1
            ) == nil
        )
        state.withLock { $0.armed = true }
        #expect(
            cache.firstMatch(
                for: rule,
                in: source,
                length: source.utf16.count,
                from: 0
            ) == nil
        )
        #expect(cache.wasCancelled)
        #expect(state.withLock { $0.calls } == 1)
    }

    @Test func anchoredAttemptRetainsAnEntryProbeCancellation() throws {
        let source = "A" + String(
            repeating: "a",
            count: RuleMatchCache.cancellationProgressMinimumLength - 1
        )
        let calls = Mutex(0)
        let cache = RuleMatchCache(
            slotCount: 1,
            units: Array(source.utf16),
            cancellationProbe: {
                calls.withLock { count in
                    count += 1
                    // The cache-window entry probe is first; cancel as the
                    // large anchored confirmation begins.
                    return count == 2
                }
            }
        )

        #expect(
            cache.firstMatch(
                for: try rule(#"(?=\b[A-Z])"#),
                in: source,
                length: source.utf16.count,
                from: 0
            ) == nil
        )
        #expect(cache.wasCancelled)
        #expect(calls.withLock { $0 } == 2)
    }

    @Test func proseInnerScanRetainsATransientCancellation() throws {
        let prosePattern = try #require(
            CommonModes.comment("//", "$").contains?
                .compactMap { $0.begin?.single }
                .first { $0.hasPrefix("[ ]+") && $0.hasSuffix("{3}") }
        )
        let source = String(
            repeating: " ",
            count: RuleMatchCache.cancellationScanStride * 2
        )
        let calls = Mutex(0)
        let cache = RuleMatchCache(
            slotCount: 1,
            units: Array(source.utf16),
            cancellationProbe: {
                calls.withLock { count in
                    count += 1
                    return count == 1
                }
            }
        )

        #expect(
            cache.firstMatch(
                for: try rule(prosePattern),
                in: source,
                length: source.utf16.count,
                from: 0
            ) == nil
        )
        #expect(cache.wasCancelled)
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func stickyCacheCancellationSkipsLaterRules() throws {
        let prosePattern = try #require(
            CommonModes.comment("//", "$").contains?
                .compactMap { $0.begin?.single }
                .first { $0.hasPrefix("[ ]+") && $0.hasSuffix("{3}") }
        )
        let source = String(
            repeating: " ",
            count: RuleMatchCache.cancellationScanStride * 2
        )
        let calls = Mutex(0)
        let cache = RuleMatchCache(
            slotCount: 2,
            units: Array(source.utf16),
            cancellationProbe: {
                calls.withLock { count in
                    count += 1
                    return count == 1
                }
            }
        )

        #expect(
            cache.firstMatch(
                for: try rule(prosePattern),
                in: source,
                length: source.utf16.count,
                from: 0
            ) == nil
        )
        #expect(cache.wasCancelled)

        // This rule would match immediately without the sticky early-out.
        #expect(
            cache.firstMatch(
                for: try rule(" ", slot: 1),
                in: source,
                length: source.utf16.count,
                from: 0
            ) == nil
        )
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func nestedAutoDetectionCancellationSkipsCandidateCompilation() throws {
        let builds = Mutex(0)
        let host = LanguageDescriptor(name: "early-cancellation-host") {
            LanguageDefinition(name: "early-cancellation-host", root: Mode())
        }
        let candidate = LanguageDescriptor(name: "early-cancellation-candidate") {
            builds.withLock { $0 += 1 }
            return LanguageDefinition(
                name: "early-cancellation-candidate",
                root: Mode(contains: [Mode(begin: "x")])
            )
        }
        let registry = LanguageRegistry(languages: [host, candidate])
        let hostLanguage = try registry.compiledLanguage(named: host.name)
        let ancestry = LanguageAncestry(
            language: hostLanguage,
            sourceLength: 1,
            initialMode: hostLanguage.root,
            parent: nil
        )
        let calls = Mutex(0)

        let result = registry.highlightAuto(
            String(repeating: "🙂", count: 16_384),
            subset: [candidate.name],
            ancestry: ancestry,
            cancellationProbe: {
                calls.withLock { count in
                    count += 1
                    return true
                }
            }
        )

        #expect(result.language == nil)
        #expect(calls.withLock { $0 } == 1)
        #expect(builds.withLock { $0 } == 0)
    }

    @Test func childCancellationIsNotDowngradedToPlainFallback() throws {
        let shouldCancel = Mutex(false)
        let delivered = Mutex(false)
        let child = LanguageDescriptor(name: "cancelling-child") {
            LanguageDefinition(
                name: "cancelling-child",
                root: Mode(contains: [
                    Mode(begin: "x", onBegin: { _, _ in
                        shouldCancel.withLock { $0 = true }
                    })
                ])
            )
        }
        let host = LanguageDescriptor(name: "cancelling-host") {
            LanguageDefinition(
                name: "cancelling-host",
                root: Mode(subLanguage: [child.name])
            )
        }
        let registry = LanguageRegistry(languages: [host, child])
        let hostLanguage = try registry.compiledLanguage(named: host.name)
        let engine = HighlightEngine(
            registry: registry,
            cancellationProbe: {
                guard shouldCancel.withLock({ $0 }) else { return false }
                return delivered.withLock { delivered in
                    guard !delivered else { return false }
                    delivered = true
                    return true
                }
            }
        )

        // The child observes the single transient true value at its final
        // probe. The parent must latch the thrown CancellationError instead
        // of treating it as an ordinary sub-language failure and returning
        // a plain fallback after the probe turns false again.
        #expect(throws: CancellationError.self) {
            _ = try engine.highlight(
                "x" as NSString,
                language: hostLanguage,
                ignoreIllegals: true
            )
        }
        #expect(delivered.withLock { $0 })
    }

    @Test func nestedAutoDetectionStopsBeforeTheNextCandidate() throws {
        let cancelled = Mutex(false)
        let firstBuilds = Mutex(0)
        let laterBuilds = Mutex(0)
        let host = LanguageDescriptor(name: "cancellation-host") {
            LanguageDefinition(name: "cancellation-host", root: Mode())
        }
        let first = LanguageDescriptor(name: "cancellation-first") {
            firstBuilds.withLock { $0 += 1 }
            return LanguageDefinition(
                name: "cancellation-first",
                root: Mode(contains: [
                    Mode(begin: "x", onBegin: { _, _ in
                        cancelled.withLock { $0 = true }
                    })
                ])
            )
        }
        let later = LanguageDescriptor(name: "cancellation-later") {
            laterBuilds.withLock { $0 += 1 }
            return LanguageDefinition(
                name: "cancellation-later",
                root: Mode(contains: [Mode(begin: "x")])
            )
        }
        let registry = LanguageRegistry(languages: [host, first, later])
        let hostLanguage = try registry.compiledLanguage(named: host.name)
        let ancestry = LanguageAncestry(
            language: hostLanguage,
            sourceLength: 1,
            initialMode: hostLanguage.root,
            parent: nil
        )

        let result = registry.highlightAuto(
            "x",
            subset: [first.name, later.name],
            ancestry: ancestry,
            cancellationProbe: { cancelled.withLock { $0 } }
        )

        #expect(result.language == nil)
        #expect(firstBuilds.withLock { $0 } == 1)
        #expect(laterBuilds.withLock { $0 } == 0)
    }
}
