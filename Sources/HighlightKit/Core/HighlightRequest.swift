import Foundation

/// Explicitly chooses how source should be highlighted.
public enum LanguageSelection: Hashable, Sendable {
    /// Highlight using a canonical language name or alias.
    case named(String)
    /// Detect the language by relevance.
    case automatic
    /// Intentionally return unhighlighted source.
    case plain
}

/// Parser semantics shared by synchronous and asynchronous requests.
public struct HighlightOptions: Hashable, Sendable {
    public var ignoreIllegals: Bool
    /// Restricts automatic detection to these canonical names or aliases.
    public var automaticSubset: [String]?

    public init(ignoreIllegals: Bool = true, automaticSubset: [String]? = nil) {
        self.ignoreIllegals = ignoreIllegals
        self.automaticSubset = automaticSubset
    }
}

/// Caps emitted tokens without stopping parsing. Relevance and continuation
/// therefore remain exact for the complete source.
public struct HighlightBudget: Hashable, Sendable {
    public let maximumTokens: Int

    public init(maximumTokens: Int) {
        precondition(maximumTokens >= 0, "maximumTokens must not be negative")
        self.maximumTokens = maximumTokens
    }
}
