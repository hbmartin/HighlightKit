import Foundation

#if DEBUG_MATCH_STATS
import Synchronization
/// Per-rule cumulative search cost, for performance work only.
/// Build with `swift test -Xswiftc -DDEBUG_MATCH_STATS`.
enum MatchStats {
    private static let perRule = Mutex<[String: (calls: Int, ns: UInt64)]>([:])

    static func record(_ pattern: String, _ ns: UInt64) {
        perRule.withLock { entries in
            var entry = entries[pattern] ?? (0, 0)
            entry.calls += 1
            entry.ns += ns
            entries[pattern] = entry
        }
    }

    static func dumpTop(_ n: Int) {
        let snapshot = perRule.withLock { $0 }
        for (pattern, e) in snapshot.sorted(by: { $0.value.ns > $1.value.ns }).prefix(n) {
            let ms = Double(e.ns) / 1e6
            print(String(format: "[rule] %8.2fms %6d calls  /%@/", ms, e.calls, String(pattern.prefix(90))))
        }
    }
}
#endif

/// What kind of event a matcher rule signals.
enum MatchKind {
    case begin(CompiledMode)
    case end
    case illegal
}

/// A begin/end/illegal rule before compilation.
struct MatchRule {
    let pattern: String
    let kind: MatchKind
}

/// One rule inside a mode's matcher, individually compiled.
///
/// highlight.js combines all rules of a mode into one big
/// `(r1)|(r2)|…` regex and re-scans from the parser's position on every
/// step. With ICU that costs a full interpreted alternation attempt per
/// input position, plus a heavyweight `NSRegularExpression` invocation
/// per step. Instead, each rule is compiled separately and the per-run
/// ``RuleMatchCache`` enumerates its matches in batches, so the number
/// of ICU invocations is proportional to the number of *matches*, not
/// engine iterations. Semantics are identical: earliest match wins,
/// ties go to the earlier rule (exactly JS alternation order).
final class CompiledRule: @unchecked Sendable {
    let pattern: String
    let kind: MatchKind
    let regex: NSRegularExpression
    /// Index into the per-run ``RuleMatchCache`` entry array; unique
    /// within a compiled language.
    let slot: Int
    /// `\B|\b` — the default "end anywhere" terminator — matches empty
    /// at every position; short-circuited without touching ICU.
    let alwaysMatchesEmpty: Bool
    /// `\b\B` — highlight.js's `MATCH_NOTHING_RE` sentinel (a
    /// boundary-and-non-boundary contradiction) — can *never* match.
    /// Short-circuited to nil: besides saving an ICU call, this avoids an
    /// `NSRegularExpression` quirk where `enumerateMatches` (used to fill
    /// the cache) reports a spurious zero-width `\b\B` match at end-of-
    /// input while `firstMatch(.anchored)` (used by the end check) does
    /// not — the disagreement otherwise deadlocks a mode whose end is
    /// this sentinel (e.g. HTTP header bodies).
    let neverMatches: Bool
    /// How the cache locates this rule's next match candidate without
    /// paying ICU's per-position interpreted attempt loop.
    enum Prefilter {
        /// No filtering possible or worthwhile: one ICU forward pass.
        case none
        /// `.?<literal>` (JavaScript's `.?html\u{60}` templates): a match
        /// contains the literal at offset 0 or 1 — scan for the literal.
        case dotOptionalLiteral([UInt16])
        /// `[ ]*(?=(W1|W2|…):)` (the comment doctag): a match is pinned
        /// to one of the literal words — scan for their occurrences and
        /// back up over the preceding spaces.
        case spacesThenLiteralColon([[UInt16]])
        /// The comment "english prose" relevance rule
        /// (`CommonModes.proseSequencePattern`): candidates need spaces
        /// followed by at least two word-ish runs — a cheap superset
        /// check; the regex still decides at candidates.
        case commentProse
        /// `[A-Za-z$_][0-9A-Za-z$_]*(?=:)` (ECMAScript object keys): a
        /// match is an identifier run ending right before a colon — scan
        /// for colons and back up over the run. ICU's forward scan
        /// attempts this at every identifier in the file; colons are far
        /// rarer than identifiers.
        case identBeforeColon
        /// The bare ECMAScript identifier `[A-Za-z$_][0-9A-Za-z$_]*`,
        /// case-sensitive rules only: both classes are pure ASCII, so
        /// the raw UTF-16 scan *is* the regex — a non-ASCII unit is
        /// simply outside both classes. No ICU fallback exists on this
        /// path; ICU still answers overlap and pre-scan queries.
        case asciiIdentifier
        /// The ECMAScript arrow-function lead-in
        /// `(\(params…\)|ident)\s*=>` — the profile's single hottest rule
        /// (nested-paren backtracking at every `(` in the file). Every
        /// match ends at a literal `=>`, and its start is computable by
        /// walking back over whitespace and either a balanced paren group
        /// or a `\w` run — so scan for arrows and confirm anchored.
        case arrowFunction
        /// A Swift rule anchored on `KwsSwift.identifier` (including
        /// zero-width lookaheads of it): every match begins at a unit
        /// satisfying `identifierHead` — an ASCII letter, `_`, or a
        /// non-ASCII unit. ICU cannot derive a start set from the giant
        /// Unicode-range alternation, and even an *anchored* attempt
        /// costs 10–45 µs because the 50-branch class is evaluated per
        /// character — so pure-ASCII candidates (essentially all real
        /// code) are decided by a hand confirm mirroring the shape, and
        /// any ≥ 0x80 unit in the walk falls back to one anchored ICU
        /// attempt. All three shapes are zero-capture-group patterns, so
        /// a synthesized result is indistinguishable from ICU's.
        case identifierHeadStart(IdentifierShape)
        /// `(?=\b[A-Z])` — the Swift type lead-in: zero-width at an
        /// uppercase letter on a word boundary.
        case uppercaseBoundary
        /// A `\b`-anchored word followed — through the rule's own `\s*`
        /// (`spacesBeforeParen`) or directly — by `(` (Swift's built-in
        /// calls, JavaScript's `functionCall`): every match maps to a
        /// `(`, so scan for parens, walk back over spaces and the word
        /// run, and confirm anchored. `firstUnits` (when present)
        /// additionally gates the run's first letter.
        case wordBeforeParen(firstUnits: Set<UInt16>?, spacesBeforeParen: Bool)
        /// Swift's protocol-composition separator `\s+&\s+(?=[A-Z]…)` —
        /// matches are pinned to the rare `&`.
        case ampersandComposition
        /// Literally `(\s*)\(` (the ECMAScript params lead-in): every
        /// `(` matches, with the preceding space run as group 1 — both
        /// ranges are computable without ICU, so matches are synthesized
        /// outright; a non-ASCII unit in the walk defers to ICU.
        case spacesThenParen
        /// The ECMAScript "value container" lead-in
        /// `(OPS|\b(case|return|throw)\b)\s*` — the profile's densest
        /// rule (~7.7k real matches/run). Operator matches are decided
        /// by an order-preserving literal table (ICU alternation picks
        /// the *first listed* alternative — `!` beats `!=`) and
        /// synthesized with all three ranges; keyword candidates and any
        /// non-ASCII adjacency take one anchored ICU attempt.
        case valueStarters(OperatorTable)
        /// Swift's punctuated-keyword alternation, hand-confirmed: each
        /// branch is a literal with a `\b`/`\B` tail decided by the next
        /// unit; listed order preserved (`init?` beats `init`).
        case punctuatedKeywords(KeywordTable)
        /// An ECMAScript numeric-literal variant: every match starts at
        /// a digit whose predecessor is not a word unit (`\b`), or — for
        /// the shapes that allow it — at `.` followed by a digit. Naive
        /// digit candidates are useless here (seven rules sharing them
        /// each pay an anchored attempt per number in the file — measured
        /// throughput-neutral), so each shape adds the cheapest condition
        /// its pattern makes *necessary*: the second unit for prefixed
        /// forms, a terminal `n` for BigInt, a reachable `[eE]` for the
        /// exponent form. The anchored regex still decides every
        /// candidate (including Unicode `\b`; an ASCII-word predecessor
        /// is a definitive rejection either way).
        case numberLiteral(NumberShape)
    }

    /// An ordered literal alternation, dispatched by first unit. Order
    /// within a bucket preserves the pattern's alternation order — ICU
    /// picks the first listed alternative that matches, not the longest.
    struct OperatorTable {
        /// Buckets indexed directly by first UTF-16 unit. The scan probes
        /// this at every input position, so dispatch is one bounds-checked
        /// array load, not a `Dictionary` hash. Construction fails closed
        /// on a non-ASCII first unit (the rule then keeps plain ICU
        /// enumeration).
        let byFirstUnit: [[[UInt16]]]
        static let dispatchWidth = 128

        /// Parses an escaped literal alternation (`!|!=|\*|\||…`).
        /// Returns nil if anything but escaped/plain literals appears.
        init?(alternation: String) {
            var buckets: [[[UInt16]]] = Array(
                repeating: [], count: Self.dispatchWidth
            )
            var current: [UInt16] = []
            var iterator = alternation.unicodeScalars.makeIterator()
            func flush() -> Bool {
                guard let first = current.first,
                      first < UInt16(Self.dispatchWidth)
                else { return false }
                buckets[Int(first)].append(current)
                current = []
                return true
            }
            while let c = iterator.next() {
                switch c {
                case "|":
                    guard flush() else { return nil }
                case "\\":
                    guard let escaped = iterator.next(),
                          CompiledRule.isLiteralRegexEscape(escaped)
                    else {
                        return nil
                    }
                    current.append(contentsOf: String(escaped).utf16)
                case ".", "*", "+", "?", "(", ")", "[", "]", "{", "}", "^", "$":
                    return nil // unescaped metacharacter — not a literal
                default:
                    current.append(contentsOf: String(c).utf16)
                }
            }
            guard flush() else { return nil }
            self.byFirstUnit = buckets
        }
    }

    /// Swift's punctuated keywords: ordered literals, each with a
    /// leading `\b` and a trailing `\b` or `\B`. Both tails reduce to
    /// the same check — the next unit must not be a word unit: after a
    /// word tail that's `\b`, and after a punctuation tail a word unit
    /// would create the boundary `\B` forbids. At end of input both
    /// assertions hold.
    struct KeywordTable {
        /// Buckets indexed directly by first UTF-16 unit — same
        /// per-position dispatch rationale as ``OperatorTable/byFirstUnit``.
        /// `parse` already guarantees an ASCII word first unit; the width
        /// guard keeps the array bound structural rather than assumed.
        let byFirstUnit: [[[UInt16]]]

        /// Derives the table from the keyword sources — each must be
        /// exactly `\b<escaped-literal>` followed by `\b` or `\B`
        /// (`\bas\?\B`, `\bfileprivate\(set\)\B`, `\binit\b`).
        /// Returns nil for any other shape, so the scan's two ASCII
        /// reductions stay structurally guaranteed rather than assumed.
        init?(sources: [String]) {
            var buckets: [[[UInt16]]] = Array(
                repeating: [], count: OperatorTable.dispatchWidth
            )
            for source in sources {
                guard let literal = Self.parse(source),
                      literal[0] < UInt16(OperatorTable.dispatchWidth)
                else { return nil }
                buckets[Int(literal[0])].append(literal)
            }
            self.byFirstUnit = buckets
        }

        /// Parses one `\b<escaped-literal>(\b|\B)` source into UTF-16
        /// units, rejecting anything that is not a plain literal (a
        /// mid-literal assertion, an unescaped metacharacter, a class
        /// escape like `\d`) and any branch whose boundary assertions
        /// the scan cannot decide in ASCII: the leading `\b` reduces to
        /// "no word unit precedes" only when the branch *starts* with an
        /// ASCII word unit, and the tail reduces to "no word unit
        /// follows" only when the assertion agrees with the last unit's
        /// word-ness (`\b` after a word unit, `\B` after punctuation).
        private static func parse(_ source: String) -> [UInt16]? {
            let scalars = Array(source.unicodeScalars)
            guard scalars.count >= 5,
                  scalars[0] == "\\", scalars[1] == "b",
                  scalars[scalars.count - 2] == "\\"
            else { return nil }
            let tail = scalars[scalars.count - 1]
            guard tail == "b" || tail == "B" else { return nil }
            var units: [UInt16] = []
            var i = 2
            let bodyEnd = scalars.count - 2
            while i < bodyEnd {
                let c = scalars[i]
                if c == "\\" {
                    i += 1
                    guard i < bodyEnd else { return nil } // dangling escape
                    let escaped = scalars[i]
                    guard CompiledRule.isLiteralRegexEscape(escaped) else { return nil }
                    units.append(contentsOf: String(escaped).utf16)
                } else {
                    switch c {
                    case ".", "*", "+", "?", "(", ")", "[", "]", "{", "}", "^", "$", "|":
                        return nil // unescaped metacharacter — not a literal
                    default:
                        units.append(contentsOf: String(c).utf16)
                    }
                }
                i += 1
            }
            func isWordUnit(_ u: UInt16) -> Bool {
                (u | 0x20) >= 0x61 && (u | 0x20) <= 0x7A // a-z A-Z
                    || u >= 0x30 && u <= 0x39            // 0-9
                    || u == 0x5F                         // _
            }
            guard let first = units.first, let last = units.last,
                  first < 0x80, isWordUnit(first),
                  last < 0x80, isWordUnit(last) == (tail == "b")
            else { return nil }
            return units
        }
    }

    /// Escapes that ICU interprets as one literal punctuation scalar.
    ///
    /// Deliberately a whitelist: `\\1` is a backreference, `\\d` is a
    /// character class, and alphabetic Unicode escapes carry regex
    /// semantics. Accepting any of those would let a prefilter synthesize
    /// a match the regex itself cannot produce.
    private static func isLiteralRegexEscape(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "\\", ".", "*", "+", "?", "(", ")", "[", "]", "{", "}", "^", "$", "|", "/":
            true
        default:
            false
        }
    }

    enum IdentifierShape {
        /// `KwsSwift.identifier` — the run itself is the match.
        case plain
        /// `identifier\s*:` — the match consumes through the colon.
        case withColon
        /// `(?:(?=identifier\s*:)|(?=identifier\s+identifier\s*:))` —
        /// zero-width at the first identifier.
        case parameterNameLookahead
    }

    enum NumberShape {
        /// Plain decimal: digit or `.`+digit start; matches are frequent,
        /// so no further gate pays for itself.
        case decimal
        /// Mantissa (digits, `_`, `.`) must reach `[eE]`.
        case exponent
        /// Digit run (digits, `_`) must reach `n`.
        case bigInt
        /// `0` then one of two units (`xX`, `bB`, `oO`).
        case prefixed(UInt16, UInt16)
        /// `0` then another octal digit (the legacy form).
        case legacyOctal
    }

    /// The seven `Javascript.swift` number variants, verbatim, mapped to
    /// their candidate shape. Must stay in sync with the grammar — drift
    /// means the prefilter silently stops applying (a perf regression,
    /// never a correctness one), and `NumberPrefilterTests.grammarPairing`
    /// fails to flag it.
    static let numberLiteralPatterns: [String: NumberShape] = [
        #"(\b(0|[1-9](_?[0-9])*|0[0-7]*[89][0-9]*)((\.([0-9](_?[0-9])*))|\.)?|(\.([0-9](_?[0-9])*)))[eE][+-]?([0-9](_?[0-9])*)\b"#: .exponent,
        #"\b(0|[1-9](_?[0-9])*|0[0-7]*[89][0-9]*)\b((\.([0-9](_?[0-9])*))\b|\.)?|(\.([0-9](_?[0-9])*))\b"#: .decimal,
        #"\b(0|[1-9](_?[0-9])*)n\b"#: .bigInt,
        #"\b0[xX][0-9a-fA-F](_?[0-9a-fA-F])*n?\b"#: .prefixed(
            UInt16(UInt8(ascii: "x")), UInt16(UInt8(ascii: "X"))
        ),
        #"\b0[bB][0-1](_?[0-1])*n?\b"#: .prefixed(
            UInt16(UInt8(ascii: "b")), UInt16(UInt8(ascii: "B"))
        ),
        #"\b0[oO][0-7](_?[0-7])*n?\b"#: .prefixed(
            UInt16(UInt8(ascii: "o")), UInt16(UInt8(ascii: "O"))
        ),
        #"\b0[0-7]+n?\b"#: .legacyOctal,
    ]

    let prefilter: Prefilter

    init(
        pattern: String,
        kind: MatchKind,
        options: NSRegularExpression.Options,
        language: String,
        slot: Int
    ) throws {
        self.pattern = pattern
        self.kind = kind
        self.slot = slot
        self.alwaysMatchesEmpty = pattern == #"\B|\b"#
        self.neverMatches = pattern == #"\b\B"#
        self.prefilter = Self.analyzePrefilter(
            pattern: pattern,
            caseInsensitive: options.contains(.caseInsensitive)
        )
        do {
            self.regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw HighlightError.invalidRegex(language: language, pattern: pattern, underlying: error)
        }
    }

    private static func analyzePrefilter(pattern: String, caseInsensitive: Bool) -> Prefilter {
        if pattern == CommonModes.proseSequencePattern {
            return .commentProse
        }
        // `.?<literal>` — the literal must appear at match offset 0 or 1.
        if pattern.hasPrefix(".?"), !caseInsensitive {
            let rest = String(pattern.dropFirst(2))
            if let literal = decodeLiteral(rest), !literal.isEmpty {
                return .dotOptionalLiteral(literal)
            }
        }
        // `ident(?=:)` — matches are pinned to a colon after the run.
        if pattern == Ecmascript.identRe + "(?=:)" {
            return .identBeforeColon
        }
        // The bare identifier — exact in ASCII, no confirmation needed.
        // Case-sensitive only: ICU's caseInsensitive folds *input* units
        // (e.g. U+212A KELVIN SIGN → `k` matches `[a-z]`), which a raw
        // ASCII scan cannot see.
        if !caseInsensitive, pattern == Ecmascript.identRe {
            return .asciiIdentifier
        }
        // The arrow-function lead-in — matches are pinned to `=>`.
        if pattern == #"(\([^()]*(\([^()]*(\([^()]*\)[^()]*)*\)[^()]*)*\)|[a-zA-Z_]\w*)\s*=>"# {
            return .arrowFunction
        }
        // Number literals — matches are pinned to digits.
        if let shape = Self.numberLiteralPatterns[pattern] {
            return .numberLiteral(shape)
        }
        // Swift identifier-anchored rules — matches begin at an
        // `identifierHead` unit. The grammar names these patterns.
        if pattern == KwsSwift.identifier {
            return .identifierHeadStart(.plain)
        }
        if pattern == KwsSwift.identifierWithColon {
            return .identifierHeadStart(.withColon)
        }
        if pattern == KwsSwift.functionParameterNameLookahead {
            return .identifierHeadStart(.parameterNameLookahead)
        }
        // The Swift type lead-in — zero-width at `\b[A-Z]`.
        if pattern == #"(?=\b[A-Z])"# {
            return .uppercaseBoundary
        }
        // The Swift punctuated-keyword alternation — ordered literals
        // with boundary tails, hand-confirmed from a table derived from
        // the same keyword sources.
        if !caseInsensitive, pattern == KwsSwift.regexKeywordPattern,
           let table = KeywordTable(
               sources: (KwsSwift.regexKeywordSources + KwsSwift.keywordTypes)
                   .map(KwsSwift.keywordWrapper) + KwsSwift.optionalDotKeywords
           ) {
            return .punctuatedKeywords(table)
        }
        // The ECMAScript value-container lead-in — ordered operator
        // literals (plus a keyword branch left to ICU).
        if !caseInsensitive, pattern == Ecmascript.valueContainerLeadIn,
           let table = OperatorTable(alternation: CommonModes.reStartersRe) {
            return .valueStarters(table)
        }
        // Word-then-`(` rules — matches are pinned to parens.
        if pattern == KwsSwift.builtInCallPattern {
            return .wordBeforeParen(
                firstUnits: KwsSwift.builtInFirstUnits, spacesBeforeParen: false
            )
        }
        if pattern == Ecmascript.functionCallPattern {
            return .wordBeforeParen(firstUnits: nil, spacesBeforeParen: true)
        }
        // Swift protocol composition — matches are pinned to `&`.
        if pattern == KwsSwift.protocolCompositionPattern {
            return .ampersandComposition
        }
        // The ECMAScript params lead-in — synthesizable outright.
        if pattern == #"(\s*)\("# {
            return .spacesThenParen
        }
        // `[ ]*(?=(W1|W2|…):)` — matches are pinned to the literal words.
        if !caseInsensitive, pattern.hasPrefix("[ ]*(?=("), pattern.hasSuffix("):)") {
            let inner = pattern.dropFirst("[ ]*(?=(".count).dropLast("):)".count)
            let words = inner.split(separator: "|", omittingEmptySubsequences: false)
            if !words.isEmpty, words.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isLetter) && $0.unicodeScalars.allSatisfy { $0.isASCII } }) {
                return .spacesThenLiteralColon(words.map { Array(($0 + ":").utf16) })
            }
        }
        // Note: a general "first character is one of a few punctuation
        // chars, scan for them" prefilter was measured and removed — for
        // the punctuation ICU actually sees in code it is *net negative*
        // (candidate scanning attempts the regex at too many positions;
        // ICU's internal `enumerateMatches` loop is faster). Only the
        // three shape-specialized prefilters above earn their keep. See
        // PERFORMANCE.md.
        return .none
    }

    /// Decodes a pattern consisting solely of literal characters and
    /// simple escapes into its UTF-16 units; nil if anything else occurs.
    private static func decodeLiteral(_ pattern: String) -> [UInt16]? {
        var units: [UInt16] = []
        var iterator = pattern.unicodeScalars.makeIterator()
        var pending: UnicodeScalar? = nil
        while let c = pending ?? iterator.next() {
            pending = nil
            switch c {
            case "\\":
                guard let e = iterator.next() else { return nil }
                switch e {
                case "n": units.append(10)
                case "t": units.append(9)
                case "r": units.append(13)
                case _ where !e.properties.isAlphabetic && !("0"..."9").contains(e):
                    units.append(contentsOf: String(e).utf16)
                default:
                    return nil
                }
            case ".", "*", "+", "?", "(", ")", "[", "]", "{", "}", "|", "^", "$":
                return nil // metacharacter — not a literal pattern
            default:
                units.append(contentsOf: String(c).utf16)
            }
        }
        return units
    }
}

/// Capture-group carrier for one match. ICU-produced matches retain their
/// `NSTextCheckingResult`; hand-synthesized matches describe their groups
/// inline instead of allocating one — an `NSTextCheckingResult` (plus a
/// range buffer for multi-group shapes) is a heap object per match, and
/// the parse loop only rarely asks for groups.
enum MatchGroups {
    /// No capture groups beyond the full match.
    case none
    /// Group 1 spans the first `length` units of the match; every other
    /// group did not participate. Both synthesized group shapes — the
    /// `(\s*)\(` params lead-in (group 1 = all but the paren) and the
    /// value-starter operator table (group 1 = the operator) — have this
    /// form.
    case group1(length: Int)
    /// ICU result carrying real capture-group ranges.
    case icu(NSTextCheckingResult)

    /// The (mode-relative) capture-group range within `matchRange`,
    /// with JavaScript `match[N]` semantics: out-of-range and
    /// non-participating groups both answer "no range" (JS `undefined`),
    /// where `NSTextCheckingResult.range(at:)` would raise on the former.
    func range(at group: Int, in matchRange: NSRange) -> NSRange {
        if group == 0 { return matchRange }
        guard group > 0 else { return NSRange(location: NSNotFound, length: 0) }
        switch self {
        case .none:
            return NSRange(location: NSNotFound, length: 0)
        case .group1(let length):
            return group == 1
                ? NSRange(location: matchRange.location, length: length)
                : NSRange(location: NSNotFound, length: 0)
        case .icu(let result):
            guard group < result.numberOfRanges else {
                return NSRange(location: NSNotFound, length: 0)
            }
            return result.range(at: group)
        }
    }
}

/// One cached match: its range plus capture groups. The range comes from
/// the cache's parallel arrays, so consulting a rule's next match costs
/// no Objective-C dispatch.
struct CachedMatch {
    let range: NSRange
    let groups: MatchGroups
}

/// The result of running a matcher: which rule fired and where.
struct MultiMatch {
    let range: NSRange
    let groups: MatchGroups
    let rule: CompiledRule
    /// Index of the fired rule relative to the first rule that was
    /// considered (JS `position`).
    let position: Int

    var index: Int { range.location }

    func groupRange(_ group: Int) -> NSRange {
        groups.range(at: group, in: range)
    }

    func callbackMatch(in source: NSString) -> CallbackMatch {
        CallbackMatch(source: source, groups: groups, matchRange: range)
    }
}

/// Per-run cache of every rule's matches, filled by windowed
/// enumeration.
///
/// For each rule the cache lazily materializes its (non-overlapping)
/// match sequence — the same sequence JavaScript's repeated
/// `lastIndex`-based `exec` produces — in windows of
/// ``RuleMatchCache/windowSize`` matches, amortizing the substantial
/// per-invocation cost of `NSRegularExpression` across many matches.
/// Queries walk the sequence with a monotonic cursor. A query that lands
/// *inside* a previously returned match (possible after a vetoed match
/// forces a re-scan one position later) falls back to a one-off
/// anchored-region search, because the non-overlapping sequence carries
/// no information about overlapping matches.
/// Reference type on purpose: the cache mutates on nearly every engine
/// step, and it is threaded through `exec → scan → firstMatch`. A struct
/// would force `inout` at every level, and each mutating access would pay
/// Swift's dynamic exclusivity-enforcement cost (`swift_beginAccess`);
/// profiling attributed ~10% of the parse loop to that bookkeeping. As a
/// class it is passed by reference with no borrow checking.
final class RuleMatchCache {
    static let windowSize = 512
    /// Small inputs finish before progress callbacks pay for themselves.
    /// Large inputs opt into ICU progress reporting so no-match scans can
    /// observe cancellation without waiting for the whole region.
    static let cancellationProgressMinimumLength = 1024 * 1024
    /// Foundation emitted only 99 progress callbacks while scanning one
    /// 1 MiB keyword match on the audited toolchain, so the former stride of
    /// 1,024 never sampled cancellation at the very threshold where progress
    /// reporting turns on. Sixty-four still amortizes `Task.isCancelled`
    /// heavily while guaranteeing at least one sample in that measured case.
    static let cancellationProgressCheckStride = 64
    static let cancellationScanStride = 4096

    /// Per-rule lazily materialized match sequence.
    private final class Entry {
        var groups: [MatchGroups] = []
        var starts: [Int] = []
        var ends: [Int] = []
        /// Index of the first list element not yet passed by queries.
        var cursor = 0
        /// Position the first enumeration started from (-1: not started).
        var scannedFrom = -1
        /// Where the next enumeration window resumes.
        var resumeFrom = 0
        /// No further matches exist from `resumeFrom` to end of input.
        var exhausted = false
    }

    /// Async-only state lives behind one pointer so the overwhelmingly common
    /// synchronous cache does not carry a 16-byte thick closure plus a sticky
    /// flag in every allocation.
    private final class CancellationState {
        let probe: HighlightEngine.CancellationProbe
        var wasCancelled = false

        init(probe: @escaping HighlightEngine.CancellationProbe) {
            self.probe = probe
        }
    }

    private var entries: [Entry?]
    /// The raw UTF-16 units of the input, for sparse-head scanning.
    private let units: [UInt16]
    /// Non-nil only for asynchronous auto-detection candidates. ICU's
    /// progress callbacks use it to stop a long no-match scan promptly.
    private let cancellationState: CancellationState?
    private var cancellationProbe: HighlightEngine.CancellationProbe? {
        cancellationState?.probe
    }
    /// Sticky observation of a positive probe. Production cancellation is
    /// sticky already, but retaining the observation also makes the cache
    /// correct for deterministic transient probes used by tests.
    private(set) var wasCancelled: Bool {
        get { cancellationState?.wasCancelled ?? false }
        set { cancellationState?.wasCancelled = newValue }
    }

    init(
        slotCount: Int,
        units: [UInt16],
        cancellationProbe: HighlightEngine.CancellationProbe? = nil
    ) {
        self.entries = Array(repeating: nil, count: slotCount)
        self.units = units
        self.cancellationState = cancellationProbe.map(CancellationState.init)
    }

    func firstMatch(
        for rule: CompiledRule,
        in source: String,
        length: Int,
        from location: Int
    ) -> CachedMatch? {
        // Once any cancellable scan observes cancellation, do not start ICU
        // or another hand-written prefilter for later rules. The owning
        // parser discards the candidate at the end of this matcher step.
        // Synchronous caches have no CancellationState, so this is one
        // predictable nil-pointer branch on their rule-lookup path.
        if wasCancelled { return nil }
        if rule.neverMatches { return nil }
        guard location <= length else { return nil }

        let entry: Entry
        if let existing = entries[rule.slot] {
            entry = existing
        } else {
            entry = Entry()
            entries[rule.slot] = entry
        }

        if entry.scannedFrom < 0 {
            entry.scannedFrom = location
            entry.resumeFrom = location
        } else if location < entry.scannedFrom {
            // query before the cached sequence began — rare; answer
            // directly without disturbing the cache
            return oneOffSearch(rule, in: source, length: length, from: location)
        }

        while true {
            // advance the cursor to the first cached match at/after
            // `location` (queries are almost always monotonic). Mutating
            // the class property directly measures faster than a
            // local-plus-write-back (step 32, rejected: −1.4% JS).
            while entry.cursor < entry.starts.count, entry.starts[entry.cursor] < location {
                entry.cursor += 1
            }
            // a non-monotonic query may point back before the cursor
            if entry.cursor > 0, entry.starts[entry.cursor - 1] >= location {
                return oneOffSearch(rule, in: source, length: length, from: location)
            }

            if entry.cursor < entry.starts.count {
                if entry.cursor > 0, entry.ends[entry.cursor - 1] > location {
                    // query inside the span of the previous match: the
                    // non-overlapping sequence can miss matches that
                    // start here
                    return oneOffSearch(rule, in: source, length: length, from: location)
                }
                let cursor = entry.cursor
                let start = entry.starts[cursor]
                return CachedMatch(
                    range: NSRange(location: start, length: entry.ends[cursor] - start),
                    groups: entry.groups[cursor]
                )
            }

            // past every cached match
            if let lastEnd = entry.ends.last, lastEnd > location {
                return oneOffSearch(rule, in: source, length: length, from: location)
            }
            if entry.exhausted {
                return nil
            }
            #if DEBUG_MATCH_STATS
            let t0 = DispatchTime.now().uptimeNanoseconds
            extendWindow(entry, rule: rule, in: source, length: length)
            MatchStats.record(rule.pattern, DispatchTime.now().uptimeNanoseconds - t0)
            #else
            extendWindow(entry, rule: rule, in: source, length: length)
            #endif
        }
    }

    /// Appends the next window of matches to the entry's sequence.
    private func extendWindow(
        _ entry: Entry,
        rule: CompiledRule,
        in source: String,
        length: Int
    ) {
        if length - entry.resumeFrom >= Self.cancellationProgressMinimumLength,
           let cancellationProbe,
           cancellationProbe() {
            wasCancelled = true
            entry.exhausted = true
            return
        }
        guard entry.resumeFrom <= length else {
            entry.exhausted = true
            return
        }
        switch rule.prefilter {
        case .dotOptionalLiteral(let literal):
            extendViaCandidates(entry, rule: rule, in: source, length: length) { position in
                // literal at `position` or at `position + 1` (consumed by `.`,
                // which cannot match a newline)
                if self.hasLiteral(literal, at: position) { return position }
                if position + 1 < length, self.units[position] != 10, self.hasLiteral(literal, at: position + 1) {
                    return position
                }
                return nil
            }
            return
        case .spacesThenLiteralColon(let words):
            extendViaCandidates(entry, rule: rule, in: source, length: length) { position in
                for word in words where self.hasLiteral(word, at: position) {
                    return position
                }
                return nil
            } backUp: { wordPosition, lowerBound in
                // `[ ]*` — leftmost match starts at the beginning of the
                // run of spaces directly before the word
                switch self.scanSpacesBackward(
                    from: wordPosition, lowerBound: lowerBound
                ) {
                case .at(let start): return start
                case .unicode, .cancelled: return wordPosition
                }
            }
            return
        case .commentProse:
            let lowerBound = entry.resumeFrom
            let space = UInt16(UInt8(ascii: " "))
            extendViaCandidates(entry, rule: rule, in: source, length: length) { position in
                // Only the first available unit of a space run can be the
                // leftmost `[ ]+` match. Re-testing every suffix makes a long
                // all-space buffer quadratic.
                guard self.units[position] == space,
                      position == lowerBound || self.units[position - 1] != space
                else { return nil }
                return self.proseCandidate(at: position, length: length)
                    ? position : nil
            }
            return
        case .asciiIdentifier:
            extendAsciiIdentifier(entry, length: length)
            return
        case .identBeforeColon:
            extendViaCandidates(entry, rule: rule, in: source, length: length) { position in
                // a colon directly preceded by an identifier character
                if self.units[position] == UInt16(UInt8(ascii: ":")), position > 0,
                   Self.isIdentBody(self.units[position - 1]) {
                    return position
                }
                return nil
            } backUp: { colon, lowerBound in
                // leftmost match start: the beginning of the identifier
                // run (never before `lowerBound` — a resume mid-run
                // legitimately matches the run's tail), advanced to the
                // first unit that can *start* a match (digits can't)
                let runStart: Int
                switch self.scanIdentifierBodyBackward(
                    from: colon, lowerBound: lowerBound
                ) {
                case .at(let start): runStart = start
                case .unicode, .cancelled: return colon
                }
                return self.scanIdentifierStartForward(
                    from: runStart, upperBound: colon
                )
            }
            return
        case .arrowFunction:
            extendArrowMatches(entry, rule: rule, in: source, length: length)
            return
        case .identifierHeadStart(let shape):
            extendIdentifierMatches(entry, rule: rule, shape: shape, in: source, length: length)
            return
        case .uppercaseBoundary:
            extendViaCandidates(entry, rule: rule, in: source, length: length) { position in
                let u = self.units[position]
                guard u >= UInt16(UInt8(ascii: "A")), u <= UInt16(UInt8(ascii: "Z")) else {
                    return nil
                }
                // `\b`: an ASCII word predecessor is a definitive
                // rejection; anything else is left to the anchored
                // attempt (ICU's `\b` knows non-ASCII word characters)
                if position == 0 || !Self.isWordASCII(self.units[position - 1]) {
                    return position
                }
                return nil
            }
            return
        case .punctuatedKeywords(let table):
            extendPunctuatedKeywords(entry, rule: rule, table: table, in: source, length: length)
            return
        case .valueStarters(let table):
            extendValueStarters(entry, rule: rule, table: table, in: source, length: length)
            return
        case .wordBeforeParen(let firstUnits, let spacesBeforeParen):
            extendWordBeforeParen(
                entry, rule: rule, firstUnits: firstUnits,
                spacesBeforeParen: spacesBeforeParen, in: source, length: length
            )
            return
        case .ampersandComposition:
            extendAmpersandComposition(entry, rule: rule, in: source, length: length)
            return
        case .spacesThenParen:
            extendSpacesThenParen(entry, rule: rule, in: source, length: length)
            return
        case .numberLiteral(let shape):
            extendViaCandidates(entry, rule: rule, in: source, length: length) { position in
                self.numberCandidate(shape, at: position, length: length) ? position : nil
            }
            return
        case .none:
            break
        }
        extendViaEnumeration(entry, rule: rule, in: source, length: length)
    }

    /// The plain path: one windowed ICU forward enumeration.
    private func extendViaEnumeration(
        _ entry: Entry,
        rule: CompiledRule,
        in source: String,
        length: Int
    ) {
        if length - entry.resumeFrom >= Self.cancellationProgressMinimumLength,
           let cancellationProbe {
            extendViaCancellableEnumeration(
                entry,
                rule: rule,
                in: source,
                length: length,
                cancellationProbe: cancellationProbe
            )
            return
        }

        var collected = 0
        var sawStop = false
        // Transparent, non-anchoring bounds so `^`, `$`, lookbehind and
        // word boundaries behave exactly like JavaScript's
        // `lastIndex`-based `exec` on the full string.
        rule.regex.enumerateMatches(
            in: source,
            options: [.withTransparentBounds, .withoutAnchoringBounds],
            range: NSRange(location: entry.resumeFrom, length: length - entry.resumeFrom)
        ) { match, _, stop in
            guard let match else { return }
            self.append(entry, match)
            collected += 1
            if collected >= Self.windowSize {
                sawStop = true
                stop.pointee = true
            }
        }
        // `append` already resumed past the last match (stepping over
        // zero-width ones); a window that ended early has no further
        // matches.
        if !sawStop {
            entry.exhausted = true
        }
    }

    /// Async-only ICU path. `.reportProgress` causes Foundation to invoke
    /// the callback even while a regex is scanning a long region with no
    /// matches, which is the otherwise-uninterruptible cancellation window.
    private func extendViaCancellableEnumeration(
        _ entry: Entry,
        rule: CompiledRule,
        in source: String,
        length: Int,
        cancellationProbe: HighlightEngine.CancellationProbe
    ) {
        var collected = 0
        var sawWindowStop = false
        var cancelled = false
        var callbacksUntilCancellationCheck = Self.cancellationProgressCheckStride
        rule.regex.enumerateMatches(
            in: source,
            options: [
                .withTransparentBounds,
                .withoutAnchoringBounds,
                .reportProgress,
            ],
            range: NSRange(location: entry.resumeFrom, length: length - entry.resumeFrom)
        ) { match, _, stop in
            callbacksUntilCancellationCheck -= 1
            if callbacksUntilCancellationCheck == 0 {
                if cancellationProbe() {
                    cancelled = true
                    stop.pointee = true
                    return
                }
                callbacksUntilCancellationCheck = Self.cancellationProgressCheckStride
            }
            guard let match else { return }
            self.append(entry, match)
            collected += 1
            if collected >= Self.windowSize {
                sawWindowStop = true
                stop.pointee = true
            }
        }
        if cancelled {
            // The owning candidate is discarded. Marking the entry exhausted
            // prevents the matcher from restarting the same scan before the
            // engine observes the task's cancellation flag.
            wasCancelled = true
            entry.exhausted = true
        } else if !sawWindowStop {
            // `append` already resumed past the last match.
            entry.exhausted = true
        }
    }

    /// Sync runs receive one full-source chunk and therefore keep their
    /// original tight loop. Async candidates use fixed chunks so long Swift
    /// prefilter scans can observe cancellation without a per-unit Task query.
    private func scanChunkEnd(from position: Int, length: Int) -> Int {
        cancellationProbe == nil
            ? length
            : min(length, position + Self.cancellationScanStride)
    }

    private func stopIfCancelled(_ entry: Entry) -> Bool {
        if wasCancelled {
            entry.exhausted = true
            return true
        }
        guard cancellationProbe?() == true else { return false }
        wasCancelled = true
        entry.exhausted = true
        return true
    }

    private enum LinearScan {
        case at(Int)
        case unicode
        case cancelled
    }

    /// Walks an ASCII `\s` run toward the beginning. The no-probe branch is
    /// deliberately the original tight loop; only async auto-detect candidates
    /// pay for fixed-size chunks and cancellation queries.
    private func scanWhitespaceBackward(from position: Int, lowerBound: Int) -> LinearScan {
        guard let cancellationProbe else {
            var i = position
            while i > lowerBound {
                let unit = units[i - 1]
                if unit == 32 || (unit >= 9 && unit <= 13) {
                    i -= 1
                } else if unit >= 0x80 {
                    return .unicode
                } else {
                    break
                }
            }
            return .at(i)
        }

        var i = position
        while i > lowerBound {
            let chunkStart = max(lowerBound, i - Self.cancellationScanStride)
            while i > chunkStart {
                let unit = units[i - 1]
                if unit == 32 || (unit >= 9 && unit <= 13) {
                    i -= 1
                } else if unit >= 0x80 {
                    return .unicode
                } else {
                    return .at(i)
                }
            }
            if cancellationProbe() {
                wasCancelled = true
                return .cancelled
            }
        }
        return .at(i)
    }

    /// Walks an ASCII `\w` run backward, deferring Unicode membership to ICU.
    private func scanWordBackward(from position: Int, lowerBound: Int) -> LinearScan {
        guard let cancellationProbe else {
            var i = position
            while i > lowerBound {
                let unit = units[i - 1]
                if Self.isWordASCII(unit) {
                    i -= 1
                } else if unit >= 0x80 {
                    return .unicode
                } else {
                    break
                }
            }
            return .at(i)
        }

        var i = position
        while i > lowerBound {
            let chunkStart = max(lowerBound, i - Self.cancellationScanStride)
            while i > chunkStart {
                let unit = units[i - 1]
                if Self.isWordASCII(unit) {
                    i -= 1
                } else if unit >= 0x80 {
                    return .unicode
                } else {
                    return .at(i)
                }
            }
            if cancellationProbe() {
                wasCancelled = true
                return .cancelled
            }
        }
        return .at(i)
    }

    /// ECMAScript's ASCII identifier body includes `$`; a non-ASCII unit is
    /// a boundary here and the anchored regex subsequently decides `\b`.
    private func scanIdentifierBodyBackward(
        from position: Int, lowerBound: Int
    ) -> LinearScan {
        guard let cancellationProbe else {
            var i = position
            while i > lowerBound, Self.isIdentBody(units[i - 1]) {
                i -= 1
            }
            return .at(i)
        }

        var i = position
        while i > lowerBound {
            let chunkStart = max(lowerBound, i - Self.cancellationScanStride)
            while i > chunkStart, Self.isIdentBody(units[i - 1]) {
                i -= 1
            }
            if i > chunkStart { return .at(i) }
            if cancellationProbe() {
                wasCancelled = true
                return .cancelled
            }
        }
        return .at(i)
    }

    private func scanSpacesBackward(from position: Int, lowerBound: Int) -> LinearScan {
        let space = UInt16(UInt8(ascii: " "))
        guard let cancellationProbe else {
            var i = position
            while i > lowerBound, units[i - 1] == space { i -= 1 }
            return .at(i)
        }

        var i = position
        while i > lowerBound {
            let chunkStart = max(lowerBound, i - Self.cancellationScanStride)
            while i > chunkStart, units[i - 1] == space { i -= 1 }
            if i > chunkStart { return .at(i) }
            if cancellationProbe() {
                wasCancelled = true
                return .cancelled
            }
        }
        return .at(i)
    }

    private func scanIdentifierStartForward(from position: Int, upperBound: Int) -> Int {
        guard let cancellationProbe else {
            var i = position
            while i < upperBound, !Self.isIdentStart(units[i]) { i += 1 }
            return i
        }

        var i = position
        while i < upperBound {
            let chunkEnd = min(upperBound, i + Self.cancellationScanStride)
            while i < chunkEnd, !Self.isIdentStart(units[i]) { i += 1 }
            if i < chunkEnd { return i }
            if cancellationProbe() {
                wasCancelled = true
                return i
            }
        }
        return i
    }

    private func scanWordForward(from position: Int, length: Int) -> LinearScan {
        guard let cancellationProbe else {
            var i = position
            while i < length {
                let unit = units[i]
                if Self.isWordASCII(unit) {
                    i += 1
                } else {
                    return unit >= 0x80 ? .unicode : .at(i)
                }
            }
            return .at(i)
        }

        var i = position
        while i < length {
            let chunkEnd = min(length, i + Self.cancellationScanStride)
            while i < chunkEnd {
                let unit = units[i]
                if Self.isWordASCII(unit) {
                    i += 1
                } else {
                    return unit >= 0x80 ? .unicode : .at(i)
                }
            }
            if cancellationProbe() {
                wasCancelled = true
                return .cancelled
            }
        }
        return .at(i)
    }

    private func scanWhitespaceForward(from position: Int, length: Int) -> LinearScan {
        guard let cancellationProbe else {
            var i = position
            while i < length {
                let unit = units[i]
                if unit == 32 || (unit >= 9 && unit <= 13) {
                    i += 1
                } else {
                    return unit >= 0x80 ? .unicode : .at(i)
                }
            }
            return .at(i)
        }

        var i = position
        while i < length {
            let chunkEnd = min(length, i + Self.cancellationScanStride)
            while i < chunkEnd {
                let unit = units[i]
                if unit == 32 || (unit >= 9 && unit <= 13) {
                    i += 1
                } else {
                    return unit >= 0x80 ? .unicode : .at(i)
                }
            }
            if cancellationProbe() {
                wasCancelled = true
                return .cancelled
            }
        }
        return .at(i)
    }

    /// One arrow's possible match start, walked back from the `=>`.
    private enum ArrowCandidate {
        case at(Int)
        /// No match can end at this arrow.
        case none
        /// The walk touched a non-ASCII unit. ICU's `\s`/`\w` classes are
        /// Unicode-aware (NBSP is `\s`; é is `\w`), so the ASCII walk
        /// cannot decide — the caller falls back to ICU for the window.
        case unicode
        case cancelled
    }

    /// Fills the arrow-function rule's entire remaining match sequence.
    ///
    /// Every match of `(\(params…\)|ident)\s*=>` ends at a literal `=>`,
    /// and per arrow exactly one start position is possible: back over
    /// whitespace, then either to the `(` balancing the closing paren
    /// (the regex re-checks its own nesting-depth limit) or to the first
    /// startable unit of the `\w` run. Nested arrows make candidate
    /// starts non-monotonic in arrow order (`(a,(b) => c) => d` — the
    /// outer match starts first), so candidates are batch-collected and
    /// attempted in start order; anchored ICU attempts keep semantics
    /// exact. False candidates are impossible by construction: a failed
    /// anchored attempt at the unique start proves no match ends at that
    /// arrow (interior starts cannot reach the arrow past the `)` that
    /// made the walk stop).
    private func extendArrowMatches(
        _ entry: Entry,
        rule: CompiledRule,
        in source: String,
        length: Int
    ) {
        let eq = UInt16(UInt8(ascii: "="))
        let gt = UInt16(UInt8(ascii: ">"))
        let lowerBound = entry.resumeFrom

        var candidates: [Int] = []
        var i = lowerBound
        while i + 1 < length {
            let chunkEnd = min(
                scanChunkEnd(from: i, length: length),
                length - 1
            )
            while i < chunkEnd {
                guard units[i] == eq, units[i + 1] == gt else {
                    i += 1
                    continue
                }
                switch arrowCandidateStart(arrow: i, lowerBound: lowerBound) {
                case .at(let start):
                    candidates.append(start)
                case .none:
                    break
                case .unicode:
                    extendViaEnumeration(entry, rule: rule, in: source, length: length)
                    return
                case .cancelled:
                    entry.exhausted = true
                    return
                }
                i += 2
            }
            if stopIfCancelled(entry) { return }
        }

        candidates.sort()
        var cursor = lowerBound
        var candidateIndex = 0
        while candidateIndex < candidates.count {
            let chunkEnd = scanChunkEnd(
                from: candidateIndex,
                length: candidates.count
            )
            while candidateIndex < chunkEnd {
                let start = candidates[candidateIndex]
                candidateIndex += 1
                guard start >= cursor,
                      let match = anchoredAttempt(
                          rule, in: source, length: length, at: start
                      )
                else { continue }
                append(entry, match)
                cursor = entry.ends[entry.ends.count - 1]
            }
            if stopIfCancelled(entry) { return }
        }
        entry.resumeFrom = length
        entry.exhausted = true
    }

    /// Appends one ICU match to the entry and advances its resume point.
    @inline(__always)
    private func append(_ entry: Entry, _ result: NSTextCheckingResult) {
        let range = result.range
        entry.groups.append(.icu(result))
        entry.starts.append(range.location)
        entry.ends.append(range.location + range.length)
        entry.resumeFrom = max(range.location + range.length, range.location + 1)
    }

    /// Appends one synthesized match — no `NSTextCheckingResult` is
    /// allocated; the capture groups are described inline.
    @inline(__always)
    private func appendSynthesized(
        _ entry: Entry, range: NSRange, groups: MatchGroups
    ) {
        entry.groups.append(groups)
        entry.starts.append(range.location)
        entry.ends.append(range.location + range.length)
        entry.resumeFrom = max(range.location + range.length, range.location + 1)
    }

    /// Word-then-`(` rules: every match is a word run reaching a `(`
    /// (directly, or through the rule's own `\s*`). Scans for parens,
    /// walks back, and confirms with one anchored attempt (which decides
    /// `\b`, negative lookaheads, and the exact alternation). Candidate
    /// starts are monotone in paren order because word runs and space
    /// runs cannot contain `(`.
    private func extendWordBeforeParen(
        _ entry: Entry,
        rule: CompiledRule,
        firstUnits: Set<UInt16>?,
        spacesBeforeParen: Bool,
        in source: String,
        length: Int
    ) {
        let open = UInt16(UInt8(ascii: "("))
        let lowerBound = entry.resumeFrom
        var position = lowerBound
        while position < length {
            let chunkEnd = scanChunkEnd(from: position, length: length)
            scan: while position < chunkEnd {
                guard units[position] == open else {
                    position += 1
                    continue
                }
                var i = position
                if spacesBeforeParen {
                    switch scanWhitespaceBackward(from: i, lowerBound: 0) {
                    case .at(let start): i = start
                    case .unicode:
                        // ICU's `\s` may extend the gap — let it decide
                        extendViaEnumeration(entry, rule: rule, in: source, length: length)
                        return
                    case .cancelled:
                        entry.exhausted = true
                        return
                    }
                }
                // the word run; `$` included (ECMAScript identifiers)
                let dollar = UInt16(UInt8(ascii: "$"))
                let start: Int
                switch scanIdentifierBodyBackward(from: i, lowerBound: 0) {
                case .at(let value): start = value
                case .unicode:
                    extendViaEnumeration(entry, rule: rule, in: source, length: length)
                    return
                case .cancelled:
                    entry.exhausted = true
                    return
                }
                guard start < i else {
                    position += 1
                    continue scan
                }
                // Valid `\b` starts inside the run: the run start itself
                // (its predecessor is not a word unit — ICU confirms ≥ 0x80
                // cases), plus interior word-boundary transitions.
                var s = max(start, lowerBound)
                while s < i {
                    let candidateChunkEnd = scanChunkEnd(from: s, length: i)
                    while s < candidateChunkEnd {
                        let isStart = s == start
                            || (units[s - 1] == dollar) != (units[s] == dollar)
                        if isStart, firstUnits?.contains(units[s]) != false,
                           let match = anchoredAttempt(
                               rule, in: source, length: length, at: s
                           ) {
                            append(entry, match)
                            return
                        }
                        s += 1
                    }
                    if stopIfCancelled(entry) { return }
                }
                position += 1
            }
            if stopIfCancelled(entry) { return }
        }
        entry.exhausted = true
    }

    /// `\s+&\s+(?=[A-Z]…)`: matches are pinned to `&` with at least one
    /// space before it. The anchored attempt (from the space-run start,
    /// clamped at the resume point — a run suffix is still `\s+`)
    /// decides the trailing `\s+` and the lookahead.
    private func extendAmpersandComposition(
        _ entry: Entry,
        rule: CompiledRule,
        in source: String,
        length: Int
    ) {
        let amp = UInt16(UInt8(ascii: "&"))
        let lowerBound = entry.resumeFrom
        var position = lowerBound
        while position < length {
            let chunkEnd = scanChunkEnd(from: position, length: length)
            while position < chunkEnd {
                guard units[position] == amp else {
                    position += 1
                    continue
                }
                let start: Int
                switch scanWhitespaceBackward(from: position, lowerBound: 0) {
                case .at(let value): start = value
                case .unicode:
                    // a Unicode space could push the true start earlier
                    extendViaEnumeration(entry, rule: rule, in: source, length: length)
                    return
                case .cancelled:
                    entry.exhausted = true
                    return
                }
                if start < position { // `\s+` needs at least one space
                    let attemptAt = max(start, lowerBound)
                    if attemptAt < position, let match = anchoredAttempt(
                        rule, in: source, length: length, at: attemptAt
                    ) {
                        append(entry, match)
                        return
                    }
                }
                position += 1
            }
            if stopIfCancelled(entry) { return }
        }
        entry.exhausted = true
    }

    /// The bare ECMAScript identifier `[A-Za-z$_][0-9A-Za-z$_]*`. Both
    /// classes are pure ASCII and the pattern has no assertions, so the
    /// raw UTF-16 scan decides every position exactly: a non-ASCII unit
    /// is outside both classes and either skips a start or ends a run.
    /// The run extension deliberately crosses chunk boundaries — a
    /// pathological single identifier spanning the whole input costs one
    /// tight ASCII walk (~1 ns/unit), far below the cancellation
    /// latencies the chunking exists to bound.
    private func extendAsciiIdentifier(_ entry: Entry, length: Int) {
        var position = entry.resumeFrom
        while position < length {
            let chunkEnd = scanChunkEnd(from: position, length: length)
            while position < chunkEnd {
                guard Self.isIdentStart(units[position]) else {
                    position += 1
                    continue
                }
                var end = position + 1
                while end < length, Self.isIdentBody(units[end]) {
                    end += 1
                }
                appendSynthesized(
                    entry,
                    range: NSRange(location: position, length: end - position),
                    groups: .none
                )
                return
            }
            if stopIfCancelled(entry) { return }
        }
        entry.exhausted = true
    }

    /// Literally `(\s*)\(`: every `(` is a match whose group 1 is the
    /// preceding ASCII space run — both ranges are computed directly and
    /// the result synthesized (capture count 1 → two ranges, exactly
    /// ICU's shape). A non-ASCII unit at the run boundary defers to ICU.
    private func extendSpacesThenParen(
        _ entry: Entry,
        rule: CompiledRule,
        in source: String,
        length: Int
    ) {
        let open = UInt16(UInt8(ascii: "("))
        let lowerBound = entry.resumeFrom
        var position = lowerBound
        while position < length {
            let chunkEnd = scanChunkEnd(from: position, length: length)
            while position < chunkEnd {
                guard units[position] == open else {
                    position += 1
                    continue
                }
                var start: Int
                switch scanWhitespaceBackward(from: position, lowerBound: 0) {
                case .at(let value): start = value
                case .unicode:
                    extendViaEnumeration(entry, rule: rule, in: source, length: length)
                    return
                case .cancelled:
                    entry.exhausted = true
                    return
                }
                start = max(start, lowerBound) // a run suffix still matches `\s*`
                appendSynthesized(
                    entry,
                    range: NSRange(location: start, length: position + 1 - start),
                    groups: .group1(length: position - start)
                )
                return
            }
            if stopIfCancelled(entry) { return }
        }
        entry.exhausted = true
    }

    /// Swift's punctuated keywords: at each candidate with a valid `\b`
    /// lead (non-word predecessor; ≥ 0x80 lets ICU decide), the bucket's
    /// literals are tried in the pattern's alternation order; the tail
    /// requires a non-word successor, and a ≥ 0x80 successor defers the
    /// whole position to one anchored ICU attempt.
    private func extendPunctuatedKeywords(
        _ entry: Entry,
        rule: CompiledRule,
        table: CompiledRule.KeywordTable,
        in source: String,
        length: Int
    ) {
        var position = entry.resumeFrom
        while position < length {
            let chunkEnd = scanChunkEnd(from: position, length: length)
            scan: while position < chunkEnd {
                let u = units[position]
                guard u < UInt16(CompiledRule.OperatorTable.dispatchWidth),
                      case let bucket = table.byFirstUnit[Int(u)],
                      !bucket.isEmpty,
                      position == 0 || !Self.isWordASCII(units[position - 1])
                else {
                    position += 1
                    continue
                }
                if position > 0, units[position - 1] >= 0x80 {
                    // unknown leading-`\b` context: one ICU attempt decides
                    if let match = anchoredAttempt(rule, in: source, length: length, at: position) {
                        append(entry, match)
                        return
                    }
                    position += 1
                    continue
                }
                for literal in bucket where hasLiteral(literal, at: position) {
                    let end = position + literal.count
                    if end < length {
                        let next = units[end]
                        if Self.isWordASCII(next) { continue } // tail fails; try later branches
                        if next >= 0x80 {
                            // unknown tail context — ICU decides all branches
                            if let match = anchoredAttempt(rule, in: source, length: length, at: position) {
                                append(entry, match)
                                return
                            }
                            position += 1
                            continue scan
                        }
                    }
                    appendSynthesized(
                        entry,
                        range: NSRange(location: position, length: literal.count),
                        groups: .none
                    )
                    return
                }
                position += 1
            }
            if stopIfCancelled(entry) { return }
        }
        entry.exhausted = true
    }

    /// The value-container lead-in: operator literals matched in
    /// alternation order and synthesized (full match incl. trailing
    /// ASCII spaces, group 1 = the operator, group 2 non-participating);
    /// `case`/`return`/`throw` candidates take one anchored ICU attempt.
    /// A ≥ 0x80 unit ending the space run defers to ICU (`\s` is
    /// Unicode-aware).
    private func extendValueStarters(
        _ entry: Entry,
        rule: CompiledRule,
        table: CompiledRule.OperatorTable,
        in source: String,
        length: Int
    ) {
        var position = entry.resumeFrom
        while position < length {
            let chunkEnd = scanChunkEnd(from: position, length: length)
            while position < chunkEnd {
                let u = units[position]
                if u < UInt16(CompiledRule.OperatorTable.dispatchWidth) {
                    let bucket = table.byFirstUnit[Int(u)]
                    for literal in bucket where hasLiteral(literal, at: position) {
                        let end: Int
                        switch scanWhitespaceForward(
                            from: position + literal.count, length: length
                        ) {
                        case .at(let value): end = value
                        case .unicode:
                            // a Unicode space could extend `\s*`
                            extendViaEnumeration(
                                entry, rule: rule, in: source, length: length
                            )
                            return
                        case .cancelled:
                            entry.exhausted = true
                            return
                        }
                        appendSynthesized(
                            entry,
                            range: NSRange(location: position, length: end - position),
                            groups: .group1(length: literal.count)
                        )
                        return
                    }
                }
                if u == 0x63 || u == 0x72 || u == 0x74, // c(ase) r(eturn) t(hrow)
                   position == 0 || !Self.isWordASCII(units[position - 1]) {
                    if let match = anchoredAttempt(rule, in: source, length: length, at: position) {
                        append(entry, match)
                        return
                    }
                }
                position += 1
            }
            if stopIfCancelled(entry) { return }
        }
        entry.exhausted = true
    }

    private func anchoredAttempt(
        _ rule: CompiledRule, in source: String, length: Int, at position: Int
    ) -> NSTextCheckingResult? {
        let range = NSRange(location: position, length: length - position)
        if range.length >= Self.cancellationProgressMinimumLength,
           let cancellationProbe {
            if cancellationProbe() {
                wasCancelled = true
                return nil
            }
            var result: NSTextCheckingResult?
            var callbacksUntilCancellationCheck =
                Self.cancellationProgressCheckStride
            rule.regex.enumerateMatches(
                in: source,
                options: [
                    .anchored,
                    .withTransparentBounds,
                    .withoutAnchoringBounds,
                    .reportProgress,
                ],
                range: range
            ) { match, _, stop in
                callbacksUntilCancellationCheck -= 1
                if callbacksUntilCancellationCheck == 0 {
                    if cancellationProbe() {
                        wasCancelled = true
                        stop.pointee = true
                        return
                    }
                    callbacksUntilCancellationCheck =
                        Self.cancellationProgressCheckStride
                }
                if let match {
                    result = match
                    stop.pointee = true
                }
            }
            return result
        }
        return rule.regex.firstMatch(
            in: source,
            options: [.anchored, .withTransparentBounds, .withoutAnchoringBounds],
            range: range
        )
    }

    private enum IdentConfirm {
        case match(end: Int)
        case none
        /// The walk touched a ≥ 0x80 unit — one anchored ICU attempt
        /// decides (the Unicode identifier classes may extend the run).
        case unicode
        case cancelled
    }

    /// Fills the next match for a Swift identifier-anchored rule.
    /// ASCII candidates are decided by ``confirmIdentifier`` and the
    /// result synthesized (the three shapes have zero capture groups, so
    /// a range-only result is exactly what ICU would produce); non-ASCII
    /// candidates get one anchored ICU attempt.
    private func extendIdentifierMatches(
        _ entry: Entry,
        rule: CompiledRule,
        shape: CompiledRule.IdentifierShape,
        in source: String,
        length: Int
    ) {
        var position = entry.resumeFrom
        while position < length {
            let chunkEnd = scanChunkEnd(from: position, length: length)
            while position < chunkEnd {
                let u = units[position]
                let asciiStart = Self.isArrowIdentStart(u)
                guard asciiStart || u >= 0x80 else {
                    position += 1
                    continue
                }
                let outcome: IdentConfirm = asciiStart
                    ? confirmIdentifier(shape, at: position, length: length)
                    : .unicode
                switch outcome {
                case .match(let end):
                    appendSynthesized(
                        entry,
                        range: NSRange(location: position, length: end - position),
                        groups: .none
                    )
                    return
                case .unicode:
                    if let match = anchoredAttempt(
                        rule, in: source, length: length, at: position
                    ) {
                        append(entry, match)
                        return
                    }
                case .none:
                    break
                case .cancelled:
                    entry.exhausted = true
                    return
                }
                position += 1
            }
            if stopIfCancelled(entry) { return }
        }
        entry.exhausted = true
    }

    /// Decides an identifier shape at an ASCII head candidate without
    /// ICU. Definitive-`none` is sound because spaces and `:` cannot
    /// occur *inside* an ASCII word run — regex backtracking cannot
    /// create a match this walk misses; only a ≥ 0x80 unit can, and
    /// that defers to ICU.
    private func confirmIdentifier(
        _ shape: CompiledRule.IdentifierShape, at start: Int, length: Int
    ) -> IdentConfirm {
        let colon = UInt16(UInt8(ascii: ":"))
        let run1: Int
        switch scanWordForward(from: start + 1, length: length) {
        case .at(let end): run1 = end
        case .unicode: return .unicode
        case .cancelled: return .cancelled
        }
        switch shape {
        case .plain:
            return .match(end: run1)
        case .withColon:
            let spaces: Int
            switch scanWhitespaceForward(from: run1, length: length) {
            case .at(let end): spaces = end
            case .unicode: return .unicode
            case .cancelled: return .cancelled
            }
            guard spaces < length, units[spaces] == colon else { return .none }
            return .match(end: spaces + 1)
        case .parameterNameLookahead:
            // `(?=ident\s*:)` — zero-width on success
            let spaces1: Int
            switch scanWhitespaceForward(from: run1, length: length) {
            case .at(let end): spaces1 = end
            case .unicode: return .unicode
            case .cancelled: return .cancelled
            }
            if spaces1 < length, units[spaces1] == colon {
                return .match(end: start)
            }
            // `(?=ident\s+ident\s*:)`
            guard spaces1 > run1, spaces1 < length else { return .none }
            let second = units[spaces1]
            if second >= 0x80 { return .unicode }
            guard Self.isArrowIdentStart(second) else { return .none }
            let run2: Int
            switch scanWordForward(from: spaces1 + 1, length: length) {
            case .at(let end): run2 = end
            case .unicode: return .unicode
            case .cancelled: return .cancelled
            }
            let spaces2: Int
            switch scanWhitespaceForward(from: run2, length: length) {
            case .at(let end): spaces2 = end
            case .unicode: return .unicode
            case .cancelled: return .cancelled
            }
            guard spaces2 < length, units[spaces2] == colon else { return .none }
            return .match(end: start)
        }
    }

    private func arrowCandidateStart(arrow: Int, lowerBound: Int) -> ArrowCandidate {
        let open = UInt16(UInt8(ascii: "("))
        let close = UInt16(UInt8(ascii: ")"))

        // `\s*` — ASCII whitespace only; ICU's `\s` goes on to NEL, NBSP
        // and the Unicode space blocks, all ≥ 0x80
        let i: Int
        switch scanWhitespaceBackward(from: arrow, lowerBound: lowerBound) {
        case .at(let start): i = start
        case .unicode: return .unicode
        case .cancelled: return .cancelled
        }
        guard i > lowerBound else { return .none }

        if units[i - 1] == close {
            // `\(…\)` — the only possible start is the balancing `(`;
            // non-paren content is opaque to the walk exactly as it is
            // to the regex's `[^()]*`
            var depth = 1
            var j = i - 1
            if let cancellationProbe {
                while j > lowerBound, depth > 0 {
                    let chunkStart = max(
                        lowerBound, j - Self.cancellationScanStride
                    )
                    while j > chunkStart, depth > 0 {
                        let u = units[j - 1]
                        if u == close {
                            depth += 1
                        } else if u == open {
                            depth -= 1
                        }
                        j -= 1
                    }
                    if cancellationProbe() {
                        wasCancelled = true
                        return .cancelled
                    }
                }
            } else {
                while j > lowerBound, depth > 0 {
                    let u = units[j - 1]
                    if u == close {
                        depth += 1
                    } else if u == open {
                        depth -= 1
                    }
                    j -= 1
                }
            }
            return depth == 0 ? .at(j) : .none
        }

        // `ident` — an ASCII `\w` run; ICU's `\w` also matches non-ASCII
        // word characters, so any such unit means the run may extend in
        // ways this walk cannot see
        var j: Int
        switch scanWordBackward(from: i, lowerBound: lowerBound) {
        case .at(let start): j = start
        case .unicode: return .unicode
        case .cancelled: return .cancelled
        }
        // digits cannot start the branch; the leftmost startable unit
        // inside the run is the true leftmost match start
        if let cancellationProbe {
            while j < i {
                let chunkEnd = min(i, j + Self.cancellationScanStride)
                while j < chunkEnd, !Self.isArrowIdentStart(units[j]) {
                    j += 1
                }
                if j < chunkEnd { break }
                if cancellationProbe() {
                    wasCancelled = true
                    return .cancelled
                }
            }
        } else {
            while j < i, !Self.isArrowIdentStart(units[j]) {
                j += 1
            }
        }
        return j < i ? .at(j) : .none
    }

    /// Cheap superset gate for the comment-prose rule: `[ ]+` then three
    /// word-ish groups, each with a trailing space (the pattern is
    /// `[ ]+(WORD[.]?[:]?([.][ ]|[ ])){3}`). False positives are fine
    /// (the regex confirms); false negatives would lose matches, so the
    /// check is deliberately loose: a word-ish run is letters,
    /// apostrophes, or hyphens, optionally followed by `.`/`:`
    /// punctuation, and groups are space-separated.
    private func proseCandidate(at position: Int, length: Int) -> Bool {
        if let cancellationProbe {
            return proseCandidateCancellable(
                at: position,
                length: length,
                cancellationProbe: cancellationProbe
            )
        }
        @inline(__always) func isLetter(_ u: UInt16) -> Bool {
            (u | 0x20) >= UInt16(UInt8(ascii: "a")) && (u | 0x20) <= UInt16(UInt8(ascii: "z"))
        }
        let space = UInt16(UInt8(ascii: " "))
        guard units[position] == space else { return false }
        var i = position
        while i < length, units[i] == space { i += 1 }

        // three word-ish runs, each followed by optional punctuation and
        // a mandatory space (the third repetition's trailing space too)
        for _ in 0..<3 {
            guard i < length, isLetter(units[i]) else { return false }
            while i < length, isLetter(units[i])
                || units[i] == UInt16(UInt8(ascii: "'"))
                || units[i] == UInt16(UInt8(ascii: "-")) {
                i += 1
            }
            while i < length, units[i] == UInt16(UInt8(ascii: "."))
                || units[i] == UInt16(UInt8(ascii: ":")) {
                i += 1
            }
            guard i < length, units[i] == space else { return false }
            while i < length, units[i] == space { i += 1 }
        }
        return true
    }

    /// Async-only form of ``proseCandidate(at:length:)``. This path is rare
    /// (the prose rule is a comment heuristic), so a small predicate helper is
    /// preferable to duplicating four chunk loops. Synchronous highlighting
    /// continues through the original branch above.
    private func proseCandidateCancellable(
        at position: Int,
        length: Int,
        cancellationProbe: HighlightEngine.CancellationProbe
    ) -> Bool {
        @inline(__always) func isLetter(_ unit: UInt16) -> Bool {
            (unit | 0x20) >= UInt16(UInt8(ascii: "a"))
                && (unit | 0x20) <= UInt16(UInt8(ascii: "z"))
        }
        let space = UInt16(UInt8(ascii: " "))
        let apostrophe = UInt16(UInt8(ascii: "'"))
        let hyphen = UInt16(UInt8(ascii: "-"))
        let period = UInt16(UInt8(ascii: "."))
        let colon = UInt16(UInt8(ascii: ":"))

        func advance(
            _ index: inout Int,
            while predicate: (UInt16) -> Bool
        ) -> Bool {
            while index < length {
                let chunkEnd = min(
                    length, index + Self.cancellationScanStride
                )
                while index < chunkEnd, predicate(units[index]) {
                    index += 1
                }
                if index < chunkEnd { return true }
                if cancellationProbe() {
                    wasCancelled = true
                    return false
                }
            }
            return true
        }

        guard units[position] == space else { return false }
        var i = position
        guard advance(&i, while: { $0 == space }) else { return false }

        for _ in 0..<3 {
            guard i < length, isLetter(units[i]) else { return false }
            guard advance(
                &i,
                while: { isLetter($0) || $0 == apostrophe || $0 == hyphen }
            ) else { return false }
            guard advance(&i, while: { $0 == period || $0 == colon }) else {
                return false
            }
            guard i < length, units[i] == space else { return false }
            guard advance(&i, while: { $0 == space }) else { return false }
        }
        return true
    }

    /// Is `position` a possible match start for a number variant? Each
    /// check is a *necessary* condition of the variant's pattern — false
    /// positives just fail the anchored attempt; false negatives are
    /// impossible by construction.
    private func numberCandidate(
        _ shape: CompiledRule.NumberShape, at position: Int, length: Int
    ) -> Bool {
        let zero = UInt16(UInt8(ascii: "0"))
        let nine = UInt16(UInt8(ascii: "9"))
        let dot = UInt16(UInt8(ascii: "."))
        let underscore = UInt16(UInt8(ascii: "_"))

        let u = units[position]
        let digitStart = u >= zero && u <= nine
            // `\b` — an ASCII word predecessor definitively kills the
            // boundary; any other unit (incl. non-ASCII word characters
            // ICU knows about) is left to the anchored attempt
            && (position == 0 || !Self.isWordASCII(units[position - 1]))

        switch shape {
        case .decimal:
            if digitStart { return true }
            return u == dot && position + 1 < length
                && units[position + 1] >= zero && units[position + 1] <= nine
        case .exponent:
            // mantissa may start at a digit or `.`+digit and must reach
            // an `e`/`E` through digits, `_`, or `.`
            let dotStart = u == dot && position + 1 < length
                && units[position + 1] >= zero && units[position + 1] <= nine
            guard digitStart || dotStart else { return false }
            if let cancellationProbe {
                var i = position
                while i < length {
                    let chunkEnd = min(
                        length, i + Self.cancellationScanStride
                    )
                    while i < chunkEnd {
                        let m = units[i]
                        if (m >= zero && m <= nine)
                            || m == underscore || m == dot {
                            i += 1
                        } else {
                            return m | 0x20 == UInt16(UInt8(ascii: "e"))
                        }
                    }
                    if cancellationProbe() {
                        wasCancelled = true
                        return false
                    }
                }
                return false
            }
            var i = position
            while i < length {
                let m = units[i]
                if (m >= zero && m <= nine) || m == underscore || m == dot {
                    i += 1
                } else {
                    return m | 0x20 == UInt16(UInt8(ascii: "e"))
                }
            }
            return false
        case .bigInt:
            guard digitStart else { return false }
            if let cancellationProbe {
                var i = position
                while i < length {
                    let chunkEnd = min(
                        length, i + Self.cancellationScanStride
                    )
                    while i < chunkEnd {
                        let m = units[i]
                        if (m >= zero && m <= nine) || m == underscore {
                            i += 1
                        } else {
                            return m == UInt16(UInt8(ascii: "n"))
                        }
                    }
                    if cancellationProbe() {
                        wasCancelled = true
                        return false
                    }
                }
                return false
            }
            var i = position
            while i < length {
                let m = units[i]
                if (m >= zero && m <= nine) || m == underscore {
                    i += 1
                } else {
                    return m == UInt16(UInt8(ascii: "n"))
                }
            }
            return false
        case .prefixed(let lower, let upper):
            return u == zero && digitStart && position + 1 < length
                && (units[position + 1] == lower || units[position + 1] == upper)
        case .legacyOctal:
            return u == zero && digitStart && position + 1 < length
                && units[position + 1] >= zero
                && units[position + 1] <= UInt16(UInt8(ascii: "7"))
        }
    }

    /// `[A-Za-z$_]` — a unit that can start the ECMAScript ident rule.
    @inline(__always)
    private static func isIdentStart(_ u: UInt16) -> Bool {
        (u | 0x20) >= UInt16(UInt8(ascii: "a")) && (u | 0x20) <= UInt16(UInt8(ascii: "z"))
            || u == UInt16(UInt8(ascii: "$")) || u == UInt16(UInt8(ascii: "_"))
    }

    /// `[0-9A-Za-z$_]` — a unit that can continue the run.
    @inline(__always)
    private static func isIdentBody(_ u: UInt16) -> Bool {
        isIdentStart(u) || (u >= UInt16(UInt8(ascii: "0")) && u <= UInt16(UInt8(ascii: "9")))
    }

    /// ASCII `\w` — `[0-9A-Za-z_]`.
    @inline(__always)
    private static func isWordASCII(_ u: UInt16) -> Bool {
        (u | 0x20) >= UInt16(UInt8(ascii: "a")) && (u | 0x20) <= UInt16(UInt8(ascii: "z"))
            || (u >= UInt16(UInt8(ascii: "0")) && u <= UInt16(UInt8(ascii: "9")))
            || u == UInt16(UInt8(ascii: "_"))
    }

    /// `[a-zA-Z_]` — a unit that can start the arrow rule's ident branch.
    @inline(__always)
    private static func isArrowIdentStart(_ u: UInt16) -> Bool {
        (u | 0x20) >= UInt16(UInt8(ascii: "a")) && (u | 0x20) <= UInt16(UInt8(ascii: "z"))
            || u == UInt16(UInt8(ascii: "_"))
    }

    @inline(__always)
    private func hasLiteral(_ literal: [UInt16], at position: Int) -> Bool {
        guard position + literal.count <= units.count else { return false }
        for (offset, unit) in literal.enumerated() where units[position + offset] != unit {
            return false
        }
        return true
    }

    /// Finds the next match of a prefiltered rule: scans the raw buffer
    /// for candidate positions and attempts an anchored ICU match only
    /// there (which keeps semantics exact — the regex still decides).
    /// Appends at most one match per call.
    private func extendViaCandidates(
        _ entry: Entry,
        rule: CompiledRule,
        in source: String,
        length: Int,
        candidate: (Int) -> Int?,
        backUp: ((_ found: Int, _ lowerBound: Int) -> Int)? = nil
    ) {
        var position = entry.resumeFrom
        while position < length {
            let chunkEnd = scanChunkEnd(from: position, length: length)
            while position < chunkEnd {
                if let found = candidate(position) {
                    let attemptAt = backUp?(found, entry.resumeFrom) ?? found
                    if wasCancelled {
                        entry.exhausted = true
                        return
                    }
                    if let match = anchoredAttempt(
                        rule, in: source, length: length, at: attemptAt
                    ) {
                        append(entry, match)
                        return
                    }
                }
                position += 1
            }
            if stopIfCancelled(entry) { return }
        }
        entry.exhausted = true
    }

    private func oneOffSearch(
        _ rule: CompiledRule,
        in source: String,
        length: Int,
        from location: Int
    ) -> CachedMatch? {
        let found: NSTextCheckingResult?
        if length - location >= Self.cancellationProgressMinimumLength,
           let cancellationProbe {
            var result: NSTextCheckingResult?
            var callbacksUntilCancellationCheck =
                Self.cancellationProgressCheckStride
            rule.regex.enumerateMatches(
                in: source,
                options: [
                    .withTransparentBounds,
                    .withoutAnchoringBounds,
                    .reportProgress,
                ],
                range: NSRange(location: location, length: length - location)
            ) { match, _, stop in
                callbacksUntilCancellationCheck -= 1
                if callbacksUntilCancellationCheck == 0 {
                    if cancellationProbe() {
                        wasCancelled = true
                        stop.pointee = true
                        return
                    }
                    callbacksUntilCancellationCheck =
                        Self.cancellationProgressCheckStride
                }
                if let match {
                    result = match
                    stop.pointee = true
                }
            }
            found = result
        } else {
            found = rule.regex.firstMatch(
                in: source,
                options: [.withTransparentBounds, .withoutAnchoringBounds],
                range: NSRange(location: location, length: length - location)
            )
        }
        return found.map { CachedMatch(range: $0.range, groups: .icu($0)) }
    }
}

/// A mode's full matcher. Port of highlight.js `ResumableMultiRegex`
/// (compile-time half — the scan cursor lives in ``MatcherCursor`` and
/// the match cache in ``RuleMatchCache``, both owned by the engine run).
final class CompiledMatcher: Sendable {
    let rules: [CompiledRule]
    /// Number of `begin` rules (JS `count`) — used for cursor wraparound.
    let beginRuleCount: Int

    init(rules: [MatchRule], options: NSRegularExpression.Options, language: String, nextSlot: inout Int) throws {
        self.rules = try rules.map { rule in
            defer { nextSlot += 1 }
            return try CompiledRule(
                pattern: rule.pattern, kind: rule.kind,
                options: options, language: language, slot: nextSlot
            )
        }
        self.beginRuleCount = rules.count { if case .begin = $0.kind { true } else { false } }
    }

    /// Earliest match among rules `startingAt...`, ties broken by rule
    /// order — identical to the combined-alternation semantics.
    private func scan(
        startingAt startIndex: Int,
        from location: Int,
        in source: String,
        length: Int,
        cache: RuleMatchCache
    ) -> MultiMatch? {
        var best: (ruleIndex: Int, match: CachedMatch)?
        for index in startIndex..<rules.count {
            let rule = rules[index]
            if rule.alwaysMatchesEmpty {
                // `\B|\b` matches empty everywhere — no ICU, no allocation
                if location <= length {
                    best = (index, CachedMatch(
                        range: NSRange(location: location, length: 0), groups: .none
                    ))
                    break // matches at `location`; later rules only tie
                }
                continue
            }
            guard let match = cache.firstMatch(for: rule, in: source, length: length, from: location) else {
                continue
            }
            if best == nil || match.range.location < best!.match.range.location {
                best = (index, match)
            }
            if match.range.location == location {
                // nothing can start earlier, and later rules only tie
                break
            }
        }
        return best.map {
            MultiMatch(
                range: $0.match.range, groups: $0.match.groups,
                rule: rules[$0.ruleIndex], position: $0.ruleIndex - startIndex
            )
        }
    }

    /// Runs one scan step, updating `cursor` exactly like highlight.js
    /// `ResumableMultiRegex.exec`.
    func exec(
        in source: String,
        length: Int,
        cursor: inout MatcherCursor,
        cache: RuleMatchCache
    ) -> MultiMatch? {
        guard !rules.isEmpty else { return nil }
        var result = scan(
            startingAt: cursor.regexIndex, from: cursor.lastIndex,
            in: source, length: length, cache: cache
        )

        // When resuming past a vetoed rule, a plain resume scan may run
        // ahead and miss earlier-rule matches between `lastIndex + 1` and
        // wherever it landed. Compare against a full scan one position
        // later and keep whichever comes first (see the long explanation
        // in highlight.js `ResumableMultiRegex`).
        if cursor.regexIndex != 0 {
            if let r = result, r.index == cursor.lastIndex {
                // valid zero-offset resume match; keep it
            } else {
                result = scan(
                    startingAt: 0, from: cursor.lastIndex + 1,
                    in: source, length: length, cache: cache
                )
            }
        }

        if let r = result {
            cursor.advance(past: r, beginRuleCount: beginRuleCount)
        }
        return result
    }
}

/// Per-scan mutable cursor for a ``CompiledMatcher``; owned by the engine's
/// parse loop so compiled modes stay immutable and shareable.
struct MatcherCursor {
    var lastIndex = 0
    var regexIndex = 0

    mutating func considerAll() {
        regexIndex = 0
    }

    mutating func advance(past match: MultiMatch, beginRuleCount: Int) {
        regexIndex += match.position + 1
        if regexIndex == beginRuleCount {
            considerAll()
        }
    }
}
