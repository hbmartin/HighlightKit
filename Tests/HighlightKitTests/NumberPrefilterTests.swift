import Foundation
import Testing
@testable import HighlightKit

/// The number-literal prefilter proposes candidates (digit after a
/// non-word unit, or `.` before a digit) and lets the anchored regex
/// decide. This suite pins the cache's sequence to raw ICU enumeration
/// for all seven grammar variants, and detects drift between the
/// hardcoded pattern set and the actual JavaScript grammar.
@Suite("Number-literal prefilter")
struct NumberPrefilterTests {
    /// Every hardcoded pattern must still exist verbatim in the compiled
    /// JavaScript grammar — otherwise the prefilter has silently stopped
    /// applying and the engine-side list needs updating.
    @Test func grammarPairing() throws {
        let language = try Highlighter.shared.registry.compiledLanguage(named: "javascript")
        var compiledPatterns: Set<String> = []
        var visited: Set<ObjectIdentifier> = []
        var queue: [CompiledMode] = [language.root]
        while let mode = queue.popLast() {
            guard visited.insert(ObjectIdentifier(mode)).inserted else { continue }
            if let starts = mode.starts { queue.append(starts) }
            for rule in mode.matcher.rules {
                compiledPatterns.insert(rule.pattern)
                if case .begin(let child) = rule.kind { queue.append(child) }
            }
        }
        for pattern in CompiledRule.numberLiteralPatterns.keys {
            #expect(
                compiledPatterns.contains(pattern),
                Comment(rawValue: "grammar drifted away from prefiltered pattern: \(pattern)")
            )
        }
    }

    private func sequences(_ input: String, pattern: String) throws -> (cache: [NSRange], reference: [NSRange]) {
        let rule = try CompiledRule(
            pattern: pattern, kind: .end, options: [.anchorsMatchLines],
            language: "test", slot: 0
        )
        #expect({ if case .numberLiteral = rule.prefilter { true } else { false } }())
        let ns = input as NSString
        var units = [UInt16](repeating: 0, count: ns.length)
        units.withUnsafeMutableBufferPointer { buffer in
            if let base = buffer.baseAddress, !buffer.isEmpty {
                ns.getCharacters(base, range: NSRange(location: 0, length: ns.length))
            }
        }
        let cache = RuleMatchCache(slotCount: 1, units: units)
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
        return (actual, expected)
    }

    @Test(arguments: Array(CompiledRule.numberLiteralPatterns.keys).sorted())
    func adversarialShapes(pattern: String) throws {
        let cases = [
            "1_000 + 0x1Fn - 0b10_1 * 0o17 / 017 % 089",
            ".5 + 1.5e-3 - 1. + 5.e2",
            "a1 b2c 1a x9y",              // digits inside identifiers: no boundary
            "é1 1é ٠5 5٠",                // non-ASCII word units around digits
            "x.5 5.toString() ..5 0._5 1__0",
            "1n 9n 0n 12345678901234567890n",
            ".e5 -1.5 +2.5 1e 1e+ 0xG 0b2 0o8",
            "0 00 000 08 09 010 0_1",
            "[1,2,3].map(n => n*2)",
            "",
            ".",
            "5",
            "٠",
        ]
        for input in cases {
            let (actual, expected) = try sequences(input, pattern: pattern)
            #expect(actual == expected, Comment(rawValue: "\(pattern.prefix(30))… on \(input.debugDescription)"))
        }
    }

    @Test(arguments: Array(CompiledRule.numberLiteralPatterns.keys).sorted())
    func seededFuzz(pattern: String) throws {
        var state: UInt64 = 0xDEADBEEFCAFEF00D
        func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        let atoms = [
            "0", "1", "9", "_", ".", "e", "E", "+", "-", "n", "x", "X",
            "b", "B", "o", "O", "7", "8", "f", "F", " ", "a", "é", "٠", "(", ")",
        ]
        for _ in 0..<600 {
            var input = ""
            for _ in 0..<(next() % 20) {
                input += atoms[Int(next() % UInt64(atoms.count))]
            }
            let (actual, expected) = try sequences(input, pattern: pattern)
            #expect(actual == expected, Comment(rawValue: "\(pattern.prefix(30))… on \(input.debugDescription)"))
        }
    }

    /// Resuming from every position of a digit-dense input must agree
    /// with ICU from that position.
    @Test func resumeFromArbitraryPositions() throws {
        let pattern = #"\b(0|[1-9](_?[0-9])*|0[0-7]*[89][0-9]*)\b((\.([0-9](_?[0-9])*))\b|\.)?|(\.([0-9](_?[0-9])*))\b"#
        let input = "x=12.5+.25e3-0x1F 089_ 1_2.3"
        let ns = input as NSString
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        for from in 0...ns.length {
            let rule = try CompiledRule(
                pattern: pattern, kind: .end, options: [.anchorsMatchLines],
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
            #expect(actual == expected, Comment(rawValue: "from \(from)"))
        }
    }
}
