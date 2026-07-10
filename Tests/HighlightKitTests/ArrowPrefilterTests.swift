import Foundation
import Testing
@testable import HighlightKit

/// The arrow-function prefilter locates candidates by hand (literal `=>`
/// scan + backward walk); a wrong walk silently loses or misplaces
/// matches. This suite pins the cache's match sequence to raw
/// `NSRegularExpression` enumeration — the ground truth — on adversarial
/// shapes and a seeded fuzz corpus.
@Suite("Arrow-function prefilter")
struct ArrowPrefilterTests {
    static let arrowPattern = #"(\([^()]*(\([^()]*(\([^()]*\)[^()]*)*\)[^()]*)*\)|[a-zA-Z_]\w*)\s*=>"#

    /// The full non-overlapping match sequence via the prefiltered cache.
    private func cacheSequence(_ input: String) throws -> [NSRange] {
        let rule = try CompiledRule(
            pattern: Self.arrowPattern, kind: .end, options: [.anchorsMatchLines],
            language: "test", slot: 0
        )
        #expect({ if case .arrowFunction = rule.prefilter { true } else { false } }())
        let ns = input as NSString
        var units = [UInt16](repeating: 0, count: ns.length)
        units.withUnsafeMutableBufferPointer { buffer in
            if let base = buffer.baseAddress, !buffer.isEmpty {
                ns.getCharacters(base, range: NSRange(location: 0, length: ns.length))
            }
        }
        let cache = RuleMatchCache(slotCount: 1, units: units)
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
        let regex = try NSRegularExpression(pattern: Self.arrowPattern, options: [.anchorsMatchLines])
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
            "(a, b) => a + b",
            "x => y",
            "(a,(b) => c) => d",            // outer match starts before inner's
            "((((x)))) =>",                 // deeper than the regex's nesting cap
            "((a,b),c) => x",
            "(\"(\") => x",                 // unbalanced-looking content
            "a9c =>",                       // digits can't start the ident branch
            "9 =>",
            "$x => y",                      // `$` is outside `\w`
            "_ => 1",
            "abc=>x",                       // zero whitespace
            "abc  \t =>",
            "(a,\nb) => c",                 // newline inside params
            ") =>",
            "( =>",
            "=>",
            "==> =>",
            "=>=>",
            "a => b => c",
            "(x => y) => z",
            "f(a, b) * 2",                  // no arrow at all
            "",
            "é => y",                       // non-ASCII before arrow
            "aé => y",                      // ICU `\w` includes é; ASCII walk must defer
            "x\u{00A0}=> y",                // NBSP is ICU `\s`
            "ab\u{85}=>",                   // NEL is ICU `\s`
            "p\u{2028} => q",               // line separator
            "(é) => y",                     // non-ASCII inside params is opaque
            "\u{1680}=>",                   // Ogham space mark
        ]
        for input in cases {
            try assertAgrees(input)
        }
    }

    @Test func seededFuzz() throws {
        // SplitMix64 — deterministic corpus, no flakiness
        var state: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        let atoms = [
            "(", ")", "=>", " ", "\t", "\n", "a", "b1", "_", "$", "x9",
            "abc", "==>", "=", ">", ",", "é", "\u{00A0}", "{", "}",
        ]
        for _ in 0..<1500 {
            var input = ""
            for _ in 0..<(next() % 24) {
                input += atoms[Int(next() % UInt64(atoms.count))]
            }
            try assertAgrees(input)
        }
    }

    /// Resuming mid-run and mid-group must agree with ICU from the same
    /// position (the cache clamps its backward walks at the resume
    /// point).
    @Test func resumeFromArbitraryPositions() throws {
        let inputs = ["abc => d", "(a,(b) => c) => d", "a9c => x", "(x) =>(y) =>"]
        for input in inputs {
            let ns = input as NSString
            let regex = try NSRegularExpression(pattern: Self.arrowPattern, options: [.anchorsMatchLines])
            for from in 0...ns.length {
                let rule = try CompiledRule(
                    pattern: Self.arrowPattern, kind: .end, options: [.anchorsMatchLines],
                    language: "test", slot: 0
                )
                var units = [UInt16](repeating: 0, count: ns.length)
                units.withUnsafeMutableBufferPointer { buffer in
                    if let base = buffer.baseAddress, !buffer.isEmpty {
                        ns.getCharacters(base, range: NSRange(location: 0, length: ns.length))
                    }
                }
                let cache = RuleMatchCache(slotCount: 1, units: units)
                let actual = cache.firstMatch(for: rule, in: input, length: ns.length, from: from)?.range
                let expected = regex.firstMatch(
                    in: input,
                    options: [.withTransparentBounds, .withoutAnchoringBounds],
                    range: NSRange(location: from, length: ns.length - from)
                )?.range
                #expect(actual == expected, Comment(rawValue: "\(input.debugDescription) from \(from)"))
            }
        }
    }
}
