import Foundation
import Testing
@testable import HighlightKit

/// Differential coverage for the Swift-grammar prefilters
/// (`identifierHeadStart`, `uppercaseBoundary`) and the tightened
/// three-run prose gate: the cache's match sequence must equal raw ICU
/// enumeration on unicode-heavy and adversarial inputs.
@Suite("Swift-grammar prefilters")
struct SwiftPrefilterTests {
    private struct MatchSignature: Equatable {
        let ranges: [NSRange]

        init(_ result: NSTextCheckingResult) {
            self.ranges = (0..<result.numberOfRanges).map(result.range(at:))
        }

        /// Resolves the cache's match through the same group accessor the
        /// engine uses, over ICU's full group count — synthesized and
        /// ICU-produced matches must be indistinguishable, including
        /// non-participating groups.
        init(_ match: CachedMatch, groupCount: Int) {
            self.ranges = (0..<groupCount).map {
                match.groups.range(at: $0, in: match.range)
            }
        }
    }

    /// The grammar-side pattern set must map to the intended prefilters
    /// on compiled rules (single source of truth, no drift possible —
    /// the engine references the same constants).
    @Test func patternsGetTheirPrefilters() throws {
        for pattern in KwsSwift.identifierHeadAnchored {
            let rule = try CompiledRule(
                pattern: pattern, kind: .end, options: [.anchorsMatchLines],
                language: "test", slot: 0
            )
            #expect({ if case .identifierHeadStart = rule.prefilter { true } else { false } }())
        }
        let upper = try CompiledRule(
            pattern: #"(?=\b[A-Z])"#, kind: .end, options: [.anchorsMatchLines],
            language: "test", slot: 0
        )
        #expect({ if case .uppercaseBoundary = upper.prefilter { true } else { false } }())

        let keyword = try CompiledRule(
            pattern: KwsSwift.regexKeywordPattern, kind: .end, options: [.anchorsMatchLines],
            language: "test", slot: 0
        )
        #expect({ if case .punctuatedKeywords = keyword.prefilter { true } else { false } }())

        let value = try CompiledRule(
            pattern: Ecmascript.valueContainerLeadIn, kind: .end, options: [.anchorsMatchLines],
            language: "test", slot: 0
        )
        #expect({ if case .valueStarters = value.prefilter { true } else { false } }())
    }

    @Test func caseInsensitiveRulesFallBackToICU() throws {
        let keyword = try CompiledRule(
            pattern: KwsSwift.regexKeywordPattern, kind: .end,
            options: [.anchorsMatchLines, .caseInsensitive], language: "test", slot: 0
        )
        let value = try CompiledRule(
            pattern: Ecmascript.valueContainerLeadIn, kind: .end,
            options: [.anchorsMatchLines, .caseInsensitive], language: "test", slot: 0
        )
        #expect({ if case .none = keyword.prefilter { true } else { false } }())
        #expect({ if case .none = value.prefilter { true } else { false } }())
        #expect(keyword.regex.firstMatch(in: "AS?", range: NSRange(location: 0, length: 3)) != nil)
        #expect(value.regex.firstMatch(in: "RETURN ", range: NSRange(location: 0, length: 7)) != nil)

        // The ASCII candidate scans below cannot see ICU folding
        // non-ASCII input units into their classes (U+017F → `s`,
        // U+212A → `k`), so each gate must decline case-insensitive
        // rules and leave them on raw ICU enumeration.
        for pattern in [
            Ecmascript.identRe + "(?=:)",
            #"\b(0|[1-9](_?[0-9])*)n\b"#,
            #"(?=\b[A-Z])"#,
            KwsSwift.builtInCallPattern,
            Ecmascript.functionCallPattern,
        ] {
            let rule = try CompiledRule(
                pattern: pattern, kind: .end,
                options: [.anchorsMatchLines, .caseInsensitive], language: "test", slot: 0
            )
            #expect(
                { if case .none = rule.prefilter { true } else { false } }(),
                Comment(rawValue: "case-insensitive rule kept a prefilter: \(pattern)")
            )
        }
    }

    @Test func literalTableParsersFailClosed() {
        #expect(CompiledRule.OperatorTable(alternation: #"!|\*|\||\("#) != nil)
        for invalid in ["", "|!", "!|", #"\"#, #"\d|!"#, #"\1|!"#, ".|!", "(x)|!"] {
            #expect(
                CompiledRule.OperatorTable(alternation: invalid) == nil,
                Comment(rawValue: "operator table accepted \(invalid.debugDescription)")
            )
        }

        #expect(CompiledRule.KeywordTable(sources: [#"\bas\?\B"#, #"\binit\b"#]) != nil)
        for invalid in [
            #"as\?\B"#, #"\bfoo"#, #"\bfoo\d\b"#, #"\bfoo\1\b"#,
            #"\bfoo.\b"#, #"\b\?foo\b"#, #"\bfoo?\b"#,
        ] {
            #expect(
                CompiledRule.KeywordTable(sources: [invalid]) == nil,
                Comment(rawValue: "keyword table accepted \(invalid.debugDescription)")
            )
        }
    }

    private static let patterns: [String] =
        Array(KwsSwift.identifierHeadAnchored).sorted()
        + [
            #"(?=\b[A-Z])"#, CommonModes.proseSequencePattern, KwsSwift.regexKeywordPattern,
            KwsSwift.builtInCallPattern, KwsSwift.protocolCompositionPattern,
            Ecmascript.functionCallPattern, #"(\s*)\("#,
            Ecmascript.valueContainerLeadIn,
        ]

    private func sequences(_ input: String, pattern: String) throws -> (cache: [NSRange], reference: [NSRange]) {
        let rule = try CompiledRule(
            pattern: pattern, kind: .end, options: [.anchorsMatchLines],
            language: "test", slot: 0
        )
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

    private func signatures(
        _ input: String,
        pattern: String
    ) throws -> (cache: [MatchSignature], reference: [MatchSignature]) {
        let rule = try CompiledRule(
            pattern: pattern, kind: .end, options: [.anchorsMatchLines],
            language: "test", slot: 0
        )
        let ns = input as NSString
        var units = [UInt16](repeating: 0, count: ns.length)
        units.withUnsafeMutableBufferPointer { buffer in
            if let base = buffer.baseAddress, !buffer.isEmpty {
                ns.getCharacters(base, range: NSRange(location: 0, length: ns.length))
            }
        }
        let cache = RuleMatchCache(slotCount: 1, units: units)
        let groupCount = rule.regex.numberOfCaptureGroups + 1
        var actual: [MatchSignature] = []
        var position = 0
        while let match = cache.firstMatch(for: rule, in: input, length: ns.length, from: position) {
            actual.append(MatchSignature(match, groupCount: groupCount))
            position = max(match.range.location + match.range.length, match.range.location + 1)
        }
        var expected: [MatchSignature] = []
        rule.regex.enumerateMatches(
            in: input,
            options: [.withTransparentBounds, .withoutAnchoringBounds],
            range: NSRange(location: 0, length: ns.length)
        ) { match, _, _ in
            if let match { expected.append(MatchSignature(match)) }
        }
        return (actual, expected)
    }

    @Test func valueStarterCapturesMatchICU() throws {
        let table = try #require(CompiledRule.OperatorTable(alternation: CommonModes.reStartersRe))
        let operators = table.byFirstUnit
            .flatMap(\.self)
            .map { String(decoding: $0, as: UTF16.self) }
        let input = (operators + ["case", "return", "throw"])
            .enumerated()
            .map { index, value in index.isMultiple(of: 2) ? value + " \t" : value }
            .joined(separator: "x")
        let (actual, expected) = try signatures(input, pattern: Ecmascript.valueContainerLeadIn)
        #expect(actual == expected)
    }

    @Test func newPrefiltersPreserveOverlapAndNonMonotonicQueries() throws {
        for (pattern, input, locations) in [
            (Ecmascript.valueContainerLeadIn, "=   == return ", [0, 1, 6, 2, 0, 8]),
            (KwsSwift.regexKeywordPattern, "as? init? Self", [0, 1, 4, 2, 0, 9]),
        ] {
            let rule = try CompiledRule(
                pattern: pattern, kind: .end, options: [.anchorsMatchLines],
                language: "test", slot: 0
            )
            let ns = input as NSString
            var units = [UInt16](repeating: 0, count: ns.length)
            units.withUnsafeMutableBufferPointer { buffer in
                if let base = buffer.baseAddress, !buffer.isEmpty {
                    ns.getCharacters(base, range: NSRange(location: 0, length: ns.length))
                }
            }
            let cache = RuleMatchCache(slotCount: 1, units: units)
            let groupCount = rule.regex.numberOfCaptureGroups + 1
            for location in locations {
                let actual = cache.firstMatch(
                    for: rule, in: input, length: ns.length, from: location
                )
                let expected = rule.regex.firstMatch(
                    in: input,
                    options: [.withTransparentBounds, .withoutAnchoringBounds],
                    range: NSRange(location: location, length: ns.length - location)
                )
                #expect(
                    actual.map { MatchSignature($0, groupCount: groupCount) }
                        == expected.map(MatchSignature.init)
                )
            }
        }
    }

    @Test(arguments: patterns)
    func adversarialShapes(pattern: String) throws {
        let cases = [
            "func f(with label: Int, _ x: Int) {}",
            "let 日本語 = 1; var économie: Double",
            "a\u{0301}x: 1",                      // combining mark is not a head
            "\u{200B}zero: width",                // zero-width space IS a head
            "9abc _x: A9 _ :",
            "ABC deF Ghi",
            "éA Aé _A A_",                        // unicode word units around uppercase
            "struct Foo: Bar & Baz {}",
            "x as? Int; try! f(); private(set) var y = self",
            "let a: Any = Self.init(); xas? as?x as ?",
            "init initX Xinit énit\u{200B}init",
            "with\u{00A0}label: Int",            // unicode space between idents
            "a  b: c", "a\tb : d", "x9_ y: :",   // \s+ and \s* boundaries
            "é: 1; aé: 2; a\u{0301}b: 3",        // unicode inside runs and heads
            "setTimeout(x); foo (bar); a.log(1)", // word-before-paren shapes
            "$f(1) f$(2) print(3) abs(x) 9(",
            "f\u{00A0}(x) (  ( ((",              // NBSP gap; bare parens
            "A & B, A &\u{00A0}B, x&y, & , a  &  b", // protocol composition
            "a !== b >>>= c <<= d ||= e",
            "x=1;y+=2,z--; return f(case_)",
            "case x: return y; throw z; xreturn returnx",
            "a =\u{00A0}b, c ==\u{2028}d",
            "// so it is done here now\n",
            "// word word word\n",
            "//A. b: c. d  e f\n",
            "don't well-known I a is on\n",
            " a  b c ",                           // double space breaks the prose reps
            "",
            ":",
            "A",
        ]
        for input in cases {
            let (actual, expected) = try sequences(input, pattern: pattern)
            #expect(actual == expected, Comment(rawValue: "\(pattern.prefix(24))… on \(input.debugDescription)"))
        }
    }

    @Test(arguments: patterns)
    func seededFuzz(pattern: String) throws {
        var state: UInt64 = 0xFEEDFACE01234567
        func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        let atoms = [
            "a", "B", "z", "_", "9", ":", " ", "  ", ".", "'", "-", "\n",
            "é", "日", "\u{200B}", "\u{0301}", "is", "so", "word", "don't", "(", "&",
            "as?", "try!", "init", "self", "Any", "Self", "open(set)", "!",
            "setTimeout", "print", "abs", "$", "&", " & ", "((", ")",
            "=", "==", "===", ">>>", "<<=", "|=", "~", "?", "case", "return", "throw",
        ]
        for _ in 0..<400 {
            var input = ""
            for _ in 0..<(next() % 18) {
                input += atoms[Int(next() % UInt64(atoms.count))]
            }
            let (actual, expected) = try sequences(input, pattern: pattern)
            #expect(actual == expected, Comment(rawValue: "\(pattern.prefix(24))… on \(input.debugDescription)"))
        }
    }
}
