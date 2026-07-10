import Foundation

/// A complete grammar for one language: the root mode plus
/// language-level metadata (port of the highlight.js `Language` object).
public struct LanguageDefinition {
    public var name: String
    public var aliases: [String]
    public var caseInsensitive: Bool
    /// Maps grammar-internal scope names to public ones.
    public var classNameAliases: [String: String]
    public var disableAutodetect: Bool
    /// Name of a language this one is a superset of (for example C++ for
    /// Arduino); breaks relevance ties during auto-detection.
    public var supersetOf: String?
    /// The top-level mode: its `keywords`, `contains` and `illegal` drive
    /// parsing from column zero.
    public var root: Mode

    public init(
        name: String,
        aliases: [String] = [],
        caseInsensitive: Bool = false,
        classNameAliases: [String: String] = [:],
        disableAutodetect: Bool = false,
        supersetOf: String? = nil,
        root: Mode
    ) {
        self.name = name
        self.aliases = aliases
        self.caseInsensitive = caseInsensitive
        self.classNameAliases = classNameAliases
        self.disableAutodetect = disableAutodetect
        self.supersetOf = supersetOf
        self.root = root
    }
}

/// A lazily built grammar: the factory is invoked (and its result
/// compiled) the first time the language is needed. The factory must
/// return a freshly constructed mode tree on every call. Factories are
/// synchronous construction closures: they must not call back into a
/// `Highlighter` or ask any registry to compile another language.
public struct LanguageDescriptor: Sendable {
    public let name: String
    public let aliases: [String]
    public let build: @Sendable () -> LanguageDefinition

    public init(name: String, aliases: [String] = [], build: @escaping @Sendable () -> LanguageDefinition) {
        self.name = name
        self.aliases = aliases
        self.build = build
    }
}
