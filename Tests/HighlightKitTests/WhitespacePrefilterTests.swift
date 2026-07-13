import Foundation
import Testing
@testable import HighlightKit

/// The bare `\s+` rule synthesizes ASCII whitespace runs and defers to
/// ICU whenever a non-ASCII unit could participate — `\s` is
/// Unicode-aware (U+0085, U+00A0, U+1680, U+2000–U+200A, U+2028/29,
/// U+202F, U+205F, U+3000). This suite pins the cache's match sequence
/// to raw `NSRegularExpression` enumeration on adversarial shapes, a
/// seeded fuzz corpus, and arbitrary resume positions.
@Suite("Whitespace-run prefilter")
struct WhitespacePrefilterTests {
    private func compiledRule() throws -> CompiledRule {
        try CompiledRule(
            pattern: #"\s+"#, kind: .end, options: [.anchorsMatchLines],
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

    private func cacheSequence(_ input: String) throws -> [NSRange] {
        let rule = try compiledRule()
        #expect({ if case .whitespaceRun = rule.prefilter { true } else { false } }())
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
        let regex = try NSRegularExpression(pattern: #"\s+"#, options: [.anchorsMatchLines])
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
            "a b\tc\nd\re\u{0B}f\u{0C}g",
            "   \t\t\n\n   ",                       // one big ASCII run
            "a\u{00A0}b",                           // NBSP is `\s` — ICU must decide
            "a \u{00A0} b",                         // Unicode space joins ASCII runs
            "x\u{0085}y",                           // NEL (the ≥0x80 unit below 0xA0)
            "p\u{2028}q\u{2029}r",                  // line/paragraph separators
            "i\u{1680}j",                           // ogham space mark
            "k\u{3000}l",                           // ideographic space
            "m\u{200B}n",                           // zero-width space is NOT \s
            "é é",                                  // non-space non-ASCII neighbors
            "run at end ",
            " leading",
            String(repeating: " ", count: 4096),    // huge run
            "a" + String(repeating: "\t", count: 300) + "\u{00A0}b", // ASCII run into NBSP
        ]
        for input in cases {
            try assertAgrees(input)
        }
    }

    @Test func seededFuzz() throws {
        // SplitMix64 — deterministic corpus, no flakiness
        var state: UInt64 = 0x243F6A8885A308D3
        func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        let atoms = [
            " ", "\t", "\n", "\r", "\u{0B}", "\u{0C}", "a", "xy", ".",
            "\u{00A0}", "\u{0085}", "\u{2028}", "\u{3000}", "\u{200B}",
            "\u{1680}", "é", "𝒂",
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
        let inputs = ["a  b\t\tc", " \u{00A0} ", "x\u{2028} y", "  ", "a"]
        for input in inputs {
            let (cache, ns) = cache(for: input)
            for from in 0...ns.length {
                let actual = cache.firstMatch(
                    for: rule, in: input, length: ns.length, from: from
                )?.range
                let expected = rule.regex.firstMatch(
                    in: input,
                    options: [.withTransparentBounds, .withoutAnchoringBounds],
                    range: NSRange(location: from, length: ns.length - from)
                )?.range
                #expect(actual == expected, Comment(rawValue: "\(input.debugDescription) from \(from)"))
            }
        }
    }
}
