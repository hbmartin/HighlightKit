import Foundation
import Testing
@testable import HighlightKit

/// The bare ECMAScript identifier rule is matched by a raw UTF-16 scan
/// with no ICU fallback at all — the two ASCII classes are the entire
/// pattern. That makes the scan the single source of truth for the
/// hottest dense rule, so this suite pins its full match sequence to raw
/// `NSRegularExpression` enumeration on adversarial shapes, a seeded
/// fuzz corpus, and arbitrary resume positions.
@Suite("ECMAScript identifier prefilter")
struct EcmaIdentifierPrefilterTests {
    private func compiledRule(
        options: NSRegularExpression.Options = [.anchorsMatchLines]
    ) throws -> CompiledRule {
        try CompiledRule(
            pattern: Ecmascript.identRe, kind: .end, options: options,
            language: "test", slot: 0
        )
    }

    private func cache(for input: String) -> (RuleMatchCache, NSString) {
        let ns = input as NSString
        var units = [UInt16](repeating: 0, count: ns.length)
        units.withUnsafeMutableBufferPointer { buffer in
            if let base = buffer.baseAddress, !buffer.isEmpty {
                ns.getCharacters(base, range: NSRange(location: 0, length: ns.length))
            }
        }
        return (RuleMatchCache(slotCount: 1, units: units), ns)
    }

    /// The full non-overlapping match sequence via the prefiltered cache.
    private func cacheSequence(_ input: String) throws -> [NSRange] {
        let rule = try compiledRule()
        #expect({ if case .asciiIdentifier = rule.prefilter { true } else { false } }())
        let (cache, ns) = cache(for: input)
        var ranges: [NSRange] = []
        var position = 0
        while let match = cache.firstMatch(for: rule, in: input, length: ns.length, from: position) {
            ranges.append(match.range)
            position = max(match.range.location + match.range.length, match.range.location + 1)
        }
        return ranges
    }

    /// Ground truth: ICU's own forward enumeration.
    private func referenceSequence(_ input: String) throws -> [NSRange] {
        let regex = try NSRegularExpression(
            pattern: Ecmascript.identRe, options: [.anchorsMatchLines]
        )
        let ns = input as NSString
        var ranges: [NSRange] = []
        regex.enumerateMatches(
            in: input,
            options: [.withTransparentBounds, .withoutAnchoringBounds],
            range: NSRange(location: 0, length: ns.length)
        ) { match, _, _ in
            if let match { ranges.append(match.range) }
        }
        return ranges
    }

    private func assertAgrees(_ input: String) throws {
        let expected = try referenceSequence(input)
        let actual = try cacheSequence(input)
        #expect(actual == expected, Comment(rawValue: input.debugDescription))
    }

    @Test func adversarialShapes() throws {
        let cases = [
            "",
            "let x = $foo._bar9 + y;",
            "9abc _9 $ _ a",
            "é éx xé x\u{0301}y",                 // non-ASCII neighbors split runs
            "\u{212A}elvin K",                    // Kelvin sign is not [A-Za-z]
            "𝒂bc a𝒃c",                            // surrogate pairs
            "\u{200B}a b\u{200B}",                // zero-width space
            "___$$$9$_a",
            "a".padding(toLength: 5000, withPad: "a", startingAt: 0), // one huge run
            String(repeating: "é", count: 300),   // no candidates at all
            "\n\t $x\n_y\t$",
        ]
        for input in cases {
            try assertAgrees(input)
        }
    }

    @Test func seededFuzz() throws {
        // SplitMix64 — deterministic corpus, no flakiness
        var state: UInt64 = 0x517CC1B727220A95
        func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        let atoms = [
            "a", "Z", "$", "_", "9", "0x", "abc", " ", "\n", ".", ",",
            "é", "\u{212A}", "𝒂", "\u{200B}", "-", "()", "€",
        ]
        for _ in 0..<1500 {
            var input = ""
            for _ in 0..<(next() % 24) {
                input += atoms[Int(next() % UInt64(atoms.count))]
            }
            try assertAgrees(input)
        }
    }

    /// Queries from arbitrary positions (mid-run, pre-scan, overlap) must
    /// agree with ICU's answer from the same position.
    @Test func resumeFromArbitraryPositions() throws {
        let rule = try compiledRule()
        let inputs = ["abc de9 $_x", "9abc", "é_a b$", "a", ""]
        for input in inputs {
            let (cache, ns) = cache(for: input)
            let regex = rule.regex
            for from in 0...ns.length {
                let actual = cache.firstMatch(
                    for: rule, in: input, length: ns.length, from: from
                )?.range
                let expected = regex.firstMatch(
                    in: input,
                    options: [.withTransparentBounds, .withoutAnchoringBounds],
                    range: NSRange(location: from, length: ns.length - from)
                )?.range
                #expect(actual == expected, Comment(rawValue: "\(input.debugDescription) from \(from)"))
            }
        }
    }

    @Test func synthesizedMatchesCarryNoGroups() throws {
        let rule = try compiledRule()
        let (cache, ns) = cache(for: "hello")
        let match = try #require(
            cache.firstMatch(for: rule, in: "hello", length: ns.length, from: 0)
        )
        #expect(match.groups.range(at: 0, in: match.range) == match.range)
        #expect(match.groups.range(at: 1, in: match.range).location == NSNotFound)
    }

    /// ICU's `.caseInsensitive` folds *input* units — U+212A KELVIN SIGN
    /// matches `[a-z]` — which a raw ASCII scan cannot see. The
    /// classification must therefore leave case-insensitive rules on
    /// plain ICU enumeration.
    @Test func caseInsensitiveRulesKeepICUEnumeration() throws {
        let rule = try compiledRule(
            options: [.anchorsMatchLines, .caseInsensitive]
        )
        #expect({ if case .asciiIdentifier = rule.prefilter { false } else { true } }())

        let input = "\u{212A}elvin"
        let (cache, ns) = cache(for: input)
        let match = try #require(
            cache.firstMatch(for: rule, in: input, length: ns.length, from: 0)
        )
        // The folded Kelvin sign participates — pinning the exact reason
        // the gate exists.
        #expect(match.range == NSRange(location: 0, length: 6))
    }
}
