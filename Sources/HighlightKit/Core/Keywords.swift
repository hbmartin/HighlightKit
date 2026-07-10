import Foundation

/// Raw keyword declarations for a mode, as written in a grammar.
///
/// Mirrors highlight.js keyword syntax: a plain list of words is shorthand
/// for the `keyword` scope; a dictionary maps scope names (`keyword`,
/// `literal`, `built_in`, `type`, …) to word lists. Each word may carry an
/// explicit relevance using the `word|relevance` form (for example
/// `"unless|10"`).
public struct Keywords: Sendable {
    /// A single scope's word list. Expressible as `"a b c"` (space
    /// separated) or `["a", "b", "c"]`.
    public struct Group: Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation, ExpressibleByArrayLiteral {
        public var words: [String]

        public init(words: [String]) {
            self.words = words
        }

        public init(stringLiteral value: String) {
            self.words = value.split(separator: " ").map(String.init)
        }

        public init(arrayLiteral elements: String...) {
            self.words = elements
        }
    }

    /// Custom pattern used to split candidate words out of plain text.
    /// Defaults to `\w+` when nil (highlight.js `$pattern`).
    public var pattern: String?

    /// Scope name → word list.
    public var groups: [String: Group]

    public init(pattern: String? = nil, _ groups: [String: Group]) {
        self.pattern = pattern
        self.groups = groups
    }

    /// Shorthand for keywords that all belong to the default
    /// `keyword` scope.
    public init(pattern: String? = nil, keyword words: Group) {
        self.pattern = pattern
        self.groups = ["keyword": words]
    }
}

extension Keywords: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public init(stringLiteral value: String) {
        self.init(keyword: Group(stringLiteral: value))
    }
}

extension Keywords: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: String...) {
        self.init(keyword: Group(words: elements))
    }
}

extension Keywords: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Group)...) {
        self.init(Dictionary(uniqueKeysWithValues: elements))
    }
}

/// Compiled keyword table: word → (scope, relevance).
typealias CompiledKeywords = [String: (scope: String, relevance: Double)]

enum KeywordCompiler {
    /// Keywords so common in prose or as identifiers that matching them
    /// contributes no relevance by default.
    static let commonKeywords: Set<String> = [
        "of", "and", "for", "in", "not", "or", "if", "then",
        "parent", "list", "value",
    ]

    static let defaultPattern = "\\w+"

    /// Port of highlight.js `compileKeywords`.
    static func compile(_ keywords: Keywords, caseInsensitive: Bool) -> CompiledKeywords {
        var compiled = CompiledKeywords(minimumCapacity: keywords.groups.values.reduce(0) { $0 + $1.words.count })
        for (scope, group) in keywords.groups {
            for entry in group.words {
                var word = entry
                var relevance: Double?
                if let bar = entry.firstIndex(of: "|") {
                    word = String(entry[..<bar])
                    relevance = Double(entry[entry.index(after: bar)...])
                }
                if caseInsensitive {
                    word = word.lowercased()
                }
                compiled[word] = (scope, relevance ?? (commonKeywords.contains(word.lowercased()) ? 0 : 1))
            }
        }
        return compiled
    }
}
