public import Foundation

/// A single highlighted run of the input.
///
/// `range` is a UTF-16 range into the highlighted string — directly usable
/// with `NSAttributedString`, `NSTextStorage` and `NSString` APIs. Plain
/// (unhighlighted) text is not represented; ranges never overlap and are
/// ordered by location.
public struct HighlightToken: Sendable, Hashable {
    /// UTF-16 range of the run in the original code.
    public let range: NSRange

    /// Scope names from outermost to innermost — for example
    /// `["string", "subst", "keyword"]` for a keyword inside a string
    /// interpolation. Never empty.
    public let scopes: [String]

    /// The innermost (most specific) scope — what a renderer typically
    /// styles the run with. Examples: `keyword`, `string`, `comment`,
    /// `title.function`, `variable.language`.
    public var scope: String { scopes[scopes.count - 1] }

    public init(range: NSRange, scopes: [String]) {
        precondition(!scopes.isEmpty, "a token must have at least one scope")
        self.range = range
        self.scopes = scopes
    }
}

/// Collects scoped text runs during a highlight pass, tracking UTF-16
/// offsets. Replaces highlight.js's HTML-producing token tree emitter.
final class TokenEmitter {
    private(set) var tokens: [HighlightToken] = []
    private var scopeStack: [String] = []
    /// Absolute UTF-16 offset of the next character to be emitted.
    private(set) var cursor = 0

    /// Emits `length` units of plain text under the current scope stack.
    func addText(length: Int) {
        guard length > 0 else { return }
        appendRun(NSRange(location: cursor, length: length), scopes: scopeStack)
        cursor += length
    }

    /// Emits a run wrapped in one extra scope (keywords, begin/end scope
    /// wraps) without the cost of pushing and popping the stack.
    func addKeyword(length: Int, scope: String) {
        guard length > 0 else { return }
        var scopes = scopeStack
        scopes.append(scope)
        appendRun(NSRange(location: cursor, length: length), scopes: scopes)
        cursor += length
    }

    func openScope(_ scope: String) {
        scopeStack.append(scope)
    }

    func closeScope() {
        // Tolerate unbalanced closes the same way highlight.js's tree
        // emitter does (it warns and continues).
        if !scopeStack.isEmpty {
            scopeStack.removeLast()
        }
    }

    /// Splices in the result of a sub-language highlight covering the next
    /// `length` units. Sub-tokens are re-based to the current cursor and
    /// nested under the current scope stack; the gaps between them inherit
    /// the current stack.
    func addSublanguage(_ subTokens: [HighlightToken], length: Int) {
        var position = 0
        for token in subTokens {
            let start = token.range.location
            if start > position {
                appendRun(NSRange(location: cursor + position, length: start - position), scopes: scopeStack)
            }
            appendRun(
                NSRange(location: cursor + start, length: token.range.length),
                scopes: scopeStack + token.scopes
            )
            position = start + token.range.length
        }
        if length > position {
            appendRun(NSRange(location: cursor + position, length: length - position), scopes: scopeStack)
        }
        cursor += length
    }

    private func appendRun(_ range: NSRange, scopes: [String]) {
        guard range.length > 0 else { return }
        guard !scopes.isEmpty else { return } // plain text: no token
        if let last = tokens.last,
           last.range.location + last.range.length == range.location,
           last.scopes == scopes {
            // merge adjacent identical runs
            tokens[tokens.count - 1] = HighlightToken(
                range: NSRange(location: last.range.location, length: last.range.length + range.length),
                scopes: scopes
            )
        } else {
            tokens.append(HighlightToken(range: range, scopes: scopes))
        }
    }
}
