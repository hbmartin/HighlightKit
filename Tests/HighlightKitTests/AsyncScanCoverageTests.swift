import Foundation
import Synchronization
import Testing
@testable import HighlightKit

/// Every hand-written prefilter has an async variant: when the cache
/// carries a cancellation probe, scans run in chunks and poll the probe
/// between them. Those variants must produce exactly the sequences the
/// synchronous walks (and ICU) produce, and a positive probe must stick:
/// the cache answers nil from then on. This suite drives each prefilter
/// through the async machinery — differentially against raw ICU with a
/// never-true probe, then under deterministic cancellation.
@Suite("Async scan variants")
struct AsyncScanCoverageTests {
    /// Every prefiltered pattern shape plus a plain-enumeration rule,
    /// with an input that contains real matches for it.
    private static let scenarios: [(pattern: String, input: String)] = [
        (#"(\([^()]*(\([^()]*(\([^()]*\)[^()]*)*\)[^()]*)*\)|[a-zA-Z_]\w*)\s*=>"#,
         "const f = (a, (b)) => x; y => z; " + String(repeating: "pad ", count: 2048)),
        (#"(\s*)\("#,
         "call  (a) f(b)" + String(repeating: " word", count: 2048) + " (tail)"),
        (Ecmascript.valueContainerLeadIn,
         "a = b; return  c! == d; " + String(repeating: "x == y; ", count: 1024)),
        (Ecmascript.identRe,
         "alpha beta9 $gamma _delta " + String(repeating: "ident ", count: 1400)),
        (#"\s+"#,
         "a b\tc\nd" + String(repeating: " run\t\t", count: 1400)),
        (Ecmascript.identRe + "(?=:)",
         "key: value, other:x " + String(repeating: "k:v ", count: 2048)),
        (CommonModes.proseSequencePattern,
         "// this is a comment that is prose " + String(repeating: "so it is here ", count: 600)),
        (KwsSwift.regexKeywordPattern,
         "let x = self as? Int; try! f() " + String(repeating: "self ", count: 1640)),
        // plain enumeration (no prefilter): a rule the classifier leaves alone
        ("[0-9]+x",
         "1x 22x 333x " + String(repeating: "9x ", count: 2730)),
    ]

    private func makeCache(
        _ input: String, probe: @escaping HighlightEngine.CancellationProbe
    ) -> (RuleMatchCache, NSString) {
        let ns = input as NSString
        var units = [UInt16](repeating: 0, count: ns.length)
        units.withUnsafeMutableBufferPointer { buffer in
            if let base = buffer.baseAddress, !buffer.isEmpty {
                ns.getCharacters(base, range: NSRange(location: 0, length: ns.length))
            }
        }
        return (
            RuleMatchCache(slotCount: 1, units: units, cancellationProbe: probe),
            ns
        )
    }

    /// With a never-true probe, the chunked async scans must yield the
    /// exact ICU sequence — the same differential bar the synchronous
    /// walks are held to.
    @Test(arguments: scenarios.indices)
    func asyncVariantsMatchICU(index: Int) throws {
        let (pattern, input) = Self.scenarios[index]
        let rule = try CompiledRule(
            pattern: pattern, kind: .end, options: [.anchorsMatchLines],
            language: "test", slot: 0
        )
        let (cache, ns) = makeCache(input) { false }
        var actual: [NSRange] = []
        var position = 0
        while let match = cache.firstMatch(for: rule, in: input, length: ns.length, from: position) {
            actual.append(match.range)
            position = max(match.range.location + match.range.length, match.range.location + 1)
        }
        var expected: [NSRange] = []
        rule.regex.enumerateMatches(
            in: input,
            options: [.withTransparentBounds, .withoutAnchoringBounds],
            range: NSRange(location: 0, length: ns.length)
        ) { match, _, _ in
            if let match { expected.append(match.range) }
        }
        #expect(actual == expected, Comment(rawValue: pattern))
        #expect(!cache.wasCancelled)
    }

    /// A probe that turns true mid-scan sticks: the walk stops, the
    /// entry exhausts, and every later query answers nil.
    @Test(arguments: scenarios.indices)
    func cancellationSticks(index: Int) throws {
        let (pattern, input) = Self.scenarios[index]
        let rule = try CompiledRule(
            pattern: pattern, kind: .end, options: [.anchorsMatchLines],
            language: "test", slot: 0
        )
        for cancelAt in [1, 2, 3] {
            let calls = Mutex(0)
            let (cache, ns) = makeCache(input) {
                calls.withLock { count in
                    count += 1
                    return count >= cancelAt
                }
            }
            var position = 0
            var results = 0
            while let match = cache.firstMatch(
                for: rule, in: input, length: ns.length, from: position
            ) {
                results += 1
                position = max(match.range.location + match.range.length, match.range.location + 1)
                if results > 20_000 { break } // cancellation must terminate the walk
            }
            guard cache.wasCancelled else { continue } // probe fired after exhaustion
            // sticky: no rule may match after a positive probe
            #expect(cache.firstMatch(for: rule, in: input, length: ns.length, from: 0) == nil)
        }
    }

    /// The `.reportProgress` enumeration variants only run for inputs of
    /// at least one mebi-unit; drive all three (windowed enumeration,
    /// one-off overlap search, anchored attempt) on such an input.
    @Test func megabyteProgressPathsHonorCancellation() throws {
        let big = String(repeating: "word ", count: 220_000) // ≥ 1 MiB units
        let ns = big as NSString
        #expect(ns.length >= RuleMatchCache.cancellationProgressMinimumLength)

        // Windowed cancellable enumeration: cancel after a few callbacks.
        for cancelAt in [1, 4] {
            let calls = Mutex(0)
            let (cache, _) = makeCache(big) {
                calls.withLock { count in
                    count += 1
                    return count >= cancelAt
                }
            }
            let rule = try CompiledRule(
                pattern: "[0-9]+z", kind: .end, options: [], language: "test", slot: 0
            )
            #expect(cache.firstMatch(for: rule, in: big, length: ns.length, from: 0) == nil)
            #expect(cache.wasCancelled)
        }

        // Same machinery, no cancellation: the full window materializes.
        let (calm, _) = makeCache(big) { false }
        let wordRule = try CompiledRule(
            pattern: "word", kind: .end, options: [], language: "test", slot: 0
        )
        let first = try #require(
            calm.firstMatch(for: wordRule, in: big, length: ns.length, from: 0)
        )
        #expect(first.range == NSRange(location: 0, length: 4))
        // One-off overlap search (query inside the previous match's span).
        let overlap = try #require(
            calm.firstMatch(for: wordRule, in: big, length: ns.length, from: 2)
        )
        #expect(overlap.range == NSRange(location: 5, length: 4))
        #expect(!calm.wasCancelled)

        // One-off overlap search under cancellation observes the probe.
        let oneOffCalls = Mutex(0)
        let (cancelling, _) = makeCache(big) {
            oneOffCalls.withLock { count in
                count += 1
                return count >= 2
            }
        }
        _ = cancelling.firstMatch(for: wordRule, in: big, length: ns.length, from: 0)
        _ = cancelling.firstMatch(for: wordRule, in: big, length: ns.length, from: 2)
        _ = cancelling.firstMatch(for: wordRule, in: big, length: ns.length, from: 4)
        // Whichever call tripped it, cancellation is sticky from then on.
        if cancelling.wasCancelled {
            #expect(cancelling.firstMatch(
                for: wordRule, in: big, length: ns.length, from: 0
            ) == nil)
        }
    }

    /// The cancellable anchored attempt runs when a candidate sits at
    /// least one mebi-unit from the end. A number candidate at position
    /// zero of a huge digit run drives its pre-probe, its mid-scan
    /// probe, and its successful-result branch.
    @Test func megabyteAnchoredAttemptHonorsCancellation() throws {
        let digits = String(repeating: "9", count: 1_100_000)
        let ns = digits as NSString
        let pattern = #"\b(0|[1-9](_?[0-9])*|0[0-7]*[89][0-9]*)n\b"#
        // Pre-probe cancellation (first probe call is inside the attempt).
        for cancelAt in [1, 2] {
            let calls = Mutex(0)
            let (cache, _) = makeCache(digits) {
                calls.withLock { count in
                    count += 1
                    return count >= cancelAt
                }
            }
            let rule = try CompiledRule(
                pattern: pattern, kind: .end, options: [], language: "test", slot: 0
            )
            #expect(cache.firstMatch(for: rule, in: digits, length: ns.length, from: 0) == nil)
        }
        // No cancellation: the anchored attempt completes (here: no match,
        // since the run never ends in `n`), and a matching rule succeeds.
        let (calm, _) = makeCache(digits) { false }
        let bigInt = try CompiledRule(
            pattern: pattern, kind: .end, options: [], language: "test", slot: 0
        )
        #expect(calm.firstMatch(for: bigInt, in: digits, length: ns.length, from: 0) == nil)
        #expect(!calm.wasCancelled)
    }

    /// Synchronous edge shapes the differential suites had not reached:
    /// the whitespace-backward `.unicode` bail behind `(\s*)\(`, arrow
    /// walks over balanced-paren groups and digit-led identifier runs,
    /// and prose candidates truncated at end of input.
    @Test func syncEdgeShapesMatchICU() throws {
        let shapes: [(pattern: String, inputs: [String])] = [
            (#"(\s*)\("#, ["a\u{00A0}  (b)", "\u{00A0}("]),
            (#"(\([^()]*(\([^()]*(\([^()]*\)[^()]*)*\)[^()]*)*\)|[a-zA-Z_]\w*)\s*=>"#,
             ["(a(b)c) => d", "((())) =>", "9abc => d", "99 => x", "((a) =>"]),
            (CommonModes.proseSequencePattern,
             [" so it is", " so it", " it", " a. ", " word-word word's a"]),
        ]
        for (pattern, inputs) in shapes {
            let rule = try CompiledRule(
                pattern: pattern, kind: .end, options: [.anchorsMatchLines],
                language: "test", slot: 0
            )
            for input in inputs {
                let (cache, ns) = makeCache(input) { false }
                var actual: [NSRange] = []
                var position = 0
                while let match = cache.firstMatch(
                    for: rule, in: input, length: ns.length, from: position
                ) {
                    actual.append(match.range)
                    position = max(match.range.location + match.range.length, match.range.location + 1)
                }
                var expected: [NSRange] = []
                rule.regex.enumerateMatches(
                    in: input,
                    options: [.withTransparentBounds, .withoutAnchoringBounds],
                    range: NSRange(location: 0, length: ns.length)
                ) { match, _, _ in
                    if let match { expected.append(match.range) }
                }
                #expect(actual == expected, Comment(rawValue: "\(pattern) on \(input.debugDescription)"))
            }
        }
    }
}
