import Foundation

/// Utilities for composing ICU regular-expression pattern strings.
///
/// This is a port of highlight.js `lib/regex.js`. Grammars compose small
/// pattern fragments into larger ones with these helpers; the combined
/// pattern is compiled once by the mode compiler.
public enum RegexSource {
    /// Escapes a literal string so it matches itself inside a pattern.
    public static func escape(_ value: String) -> String {
        var out = String()
        out.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "-", "/", "\\", "^", "$", "*", "+", "?", ".", "(", ")", "|", "[", "]", "{", "}":
                out.append("\\")
                out.append(character)
            default:
                out.append(character)
            }
        }
        return out
    }

    /// `(?=re)`
    public static func lookahead(_ pattern: String) -> String {
        "(?=\(pattern))"
    }

    /// `(?:re)*`
    public static func anyNumberOfTimes(_ pattern: String) -> String {
        "(?:\(pattern))*"
    }

    /// `(?:re)?`
    public static func optional(_ pattern: String) -> String {
        "(?:\(pattern))?"
    }

    /// Joins pattern fragments in sequence.
    public static func concat(_ patterns: String...) -> String {
        patterns.joined()
    }

    /// `(?:a|b|c)` — any of the alternatives may match.
    public static func either(_ patterns: String..., capture: Bool = false) -> String {
        either(patterns, capture: capture)
    }

    /// `(?:a|b|c)` — any of the alternatives may match.
    public static func either(_ patterns: [String], capture: Bool = false) -> String {
        "(\(capture ? "" : "?:")\(patterns.joined(separator: "|")))"
    }

    /// Counts the capturing groups in `pattern`, mirroring the group
    /// numbering ICU/JavaScript use: plain `(`, named `(?<name>` and
    /// `(?'name'` capture; `(?:`, lookarounds, and classes do not.
    public static func countCaptureGroups(_ pattern: String) -> Int {
        var count = 0
        scan(pattern) { token in
            if case .captureGroupOpen = token { count += 1 }
        }
        return count
    }

    /// Joins each pattern into its own capturing group —
    /// `(p1)<joiner>(p2)…` — renumbering any backreferences inside the
    /// individual patterns so they keep pointing at their own groups.
    ///
    /// Port of highlight.js `regex._rewriteBackreferences`.
    static func rewriteBackreferences(_ patterns: [String], joinedBy joiner: String) -> String {
        var totalCaptures = 0
        let rewritten = patterns.map { pattern -> String in
            totalCaptures += 1
            let offset = totalCaptures
            var out = String()
            out.reserveCapacity(pattern.utf16.count + 2)
            scan(pattern) { token in
                switch token {
                case .backreference(let number, let original):
                    let (renumbered, overflow) = number.addingReportingOverflow(offset)
                    // No realizable regex has Int.max capture groups. Keep a
                    // pathological escape intact instead of trapping while
                    // compiling an otherwise user-controlled grammar.
                    out += overflow ? original : "\\\(renumbered)"
                case .captureGroupOpen(let text):
                    totalCaptures += 1
                    out += text
                case .other(let text):
                    out += text
                }
            }
            return out
        }
        return rewritten.map { "(\($0))" }.joined(separator: joiner)
    }

    // MARK: - Pattern scanning

    /// A syntactically significant fragment found while scanning a pattern.
    enum PatternToken {
        /// `\N` numeric backreference; carries the referenced group number
        /// and the original text.
        case backreference(Int, String)
        /// An opening parenthesis that starts a *capturing* group
        /// (`(`, `(?<name>`, `(?'name'`); carries the original text.
        case captureGroupOpen(String)
        /// Any other run of pattern text (escapes, classes, non-capturing
        /// parens, literals) that needs no special handling.
        case other(String)
    }

    /// Scans `pattern`, emitting tokens for the constructs that affect
    /// capture-group numbering: character classes (inside which `(` and `\`
    /// lose their meaning), escapes, backreferences, and group openers.
    static func scan(_ pattern: String, _ emit: (PatternToken) -> Void) {
        let scalars = Array(pattern.unicodeScalars)
        var i = 0
        var literalStart = 0

        func flushLiteral(upTo end: Int) {
            if end > literalStart {
                emit(.other(String(String.UnicodeScalarView(scalars[literalStart..<end]))))
            }
        }

        func text(_ range: Range<Int>) -> String {
            String(String.UnicodeScalarView(scalars[range]))
        }

        while i < scalars.count {
            let c = scalars[i]
            switch c {
            case "\\":
                guard i + 1 < scalars.count else {
                    i += 1
                    continue
                }
                let next = scalars[i + 1]
                if ("1"..."9").contains(next) {
                    // numeric backreference: \1 … \99…
                    flushLiteral(upTo: i)
                    var j = i + 2
                    while j < scalars.count, ("0"..."9").contains(scalars[j]) { j += 1 }
                    let digits = text((i + 1)..<j)
                    let original = text(i..<j)
                    if let number = Int(digits) {
                        emit(.backreference(number, original))
                    } else {
                        // A pattern cannot contain enough capture groups for
                        // an integer-sized index to overflow. Preserve a
                        // pathological escape verbatim instead of silently
                        // turning it into backreference zero plus an offset.
                        emit(.other(original))
                    }
                    i = j
                    literalStart = i
                } else {
                    // any other escape — opaque, skip both scalars
                    i += 2
                }
            case "[":
                // character class: `(` and `\` lose their meaning until the
                // closing `]`; contents follow `(?:[^\\\]]|\\.)*`
                i += 1
                while i < scalars.count {
                    if scalars[i] == "\\" {
                        i += 2
                    } else if scalars[i] == "]" {
                        i += 1
                        break
                    } else {
                        i += 1
                    }
                }
            case "(":
                if i + 1 < scalars.count, scalars[i + 1] == "?" {
                    if i + 2 < scalars.count, scalars[i + 2] == "<",
                       i + 3 < scalars.count, scalars[i + 3] != "=", scalars[i + 3] != "!" {
                        // named capture `(?<name>`
                        flushLiteral(upTo: i)
                        var j = i + 3
                        while j < scalars.count, scalars[j] != ">" { j += 1 }
                        if j < scalars.count { j += 1 }
                        emit(.captureGroupOpen(text(i..<j)))
                        i = j
                        literalStart = i
                    } else if i + 2 < scalars.count, scalars[i + 2] == "'" {
                        // named capture `(?'name'`
                        flushLiteral(upTo: i)
                        var j = i + 3
                        while j < scalars.count, scalars[j] != "'" { j += 1 }
                        if j < scalars.count { j += 1 }
                        emit(.captureGroupOpen(text(i..<j)))
                        i = j
                        literalStart = i
                    } else {
                        // non-capturing group or lookaround `(?`
                        i += 2
                    }
                } else {
                    // plain capturing group
                    flushLiteral(upTo: i)
                    emit(.captureGroupOpen("("))
                    i += 1
                    literalStart = i
                }
            default:
                i += 1
            }
        }
        flushLiteral(upTo: scalars.count)
    }
}
