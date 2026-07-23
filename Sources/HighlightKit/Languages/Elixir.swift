import Foundation

extension LanguageCatalog {
    /// Elixir. Port of highlight.js `languages/elixir.js` at 08cb242.
    public static let elixir = LanguageDescriptor(name: "elixir", aliases: ["ex", "exs"]) {
        let identifier = #"[a-zA-Z_][a-zA-Z0-9_.]*(!|\?)?"#
        let method = #"[a-zA-Z_]\w*[!?=]?|[-+~]@|<<|>>|=~|===?|<=>|[<>]=?|\*\*|[-/+%^&*~`|]|\[\]=?"#
        let keywords = Keywords(
            pattern: identifier,
            [
                "keyword": Keywords.Group(words: [
                    "after", "alias", "and", "case", "catch", "cond", "defstruct",
                    "defguard", "do", "else", "end", "fn", "for", "if", "import",
                    "in", "not", "or", "quote", "raise", "receive", "require",
                    "reraise", "rescue", "try", "unless", "unquote",
                    "unquote_splicing", "use", "when", "with|0",
                ]),
                "literal": Keywords.Group(words: ["false", "nil", "true"]),
            ]
        )
        let substitution = Mode(scope: "subst", begin: #"#\{"#, end: #"\}"#, keywords: keywords)
        let number = Mode(
            scope: "number",
            begin: #"(\b0o[0-7_]+)|(\b0b[01_]+)|(\b0x[0-9a-fA-F_]+)|(-?\b[0-9][0-9_]*(\.[0-9_]+([eE][-+]?[0-9]+)?)?)"#,
            relevance: 0
        )
        let backslashEscape = Mode(scope: "char.escape", match: #"\\[\s\S]"#, relevance: 0)

        let delimiters: [(begin: String, end: String)] = [
            (#"""#, #"""#), ("'", "'"), (#"\/"#, #"\/"#), (#"\|"#, #"\|"#),
            (#"\("#, #"\)"#), (#"\["#, #"\]"#), (#"\{"#, #"\}"#), ("<", ">"),
        ]
        func escapedEnd(_ end: String) -> Mode {
            Mode(scope: "char.escape", begin: .re(#"\\"# + end), relevance: 0)
        }
        func sigilDelimiters(interpolating: Bool, modifiers: Bool = false) -> [Mode] {
            delimiters.map { delimiter in
                var contains = [escapedEnd(delimiter.end)]
                if interpolating {
                    contains.append(backslashEscape)
                    contains.append(substitution)
                }
                return Mode(
                    begin: .re(delimiter.begin),
                    end: .re(delimiter.end + (modifiers ? "[uismxfU]{0,7}" : "")),
                    contains: contains
                )
            }
        }
        // ICU requires the literal `[` to be escaped inside this class.
        let sigilLookahead = #"(?=[/|(\[{<"'])"#
        let lowercaseSigil = Mode(
            scope: "string",
            begin: .re("~[a-z]" + sigilLookahead),
            contains: sigilDelimiters(interpolating: true)
        )
        let uppercaseSigil = Mode(
            scope: "string",
            begin: .re("~[A-Z]" + sigilLookahead),
            contains: sigilDelimiters(interpolating: false)
        )
        let regexSigil = Mode(scope: "regex", variants: [
            Mode(
                begin: .re("~r" + sigilLookahead),
                contains: sigilDelimiters(interpolating: true, modifiers: true)
            ),
            Mode(
                begin: .re("~R" + sigilLookahead),
                contains: sigilDelimiters(interpolating: false, modifiers: true)
            ),
        ])
        let string = Mode(
            scope: "string",
            contains: [CommonModes.backslashEscape, substitution],
            variants: [
                Mode(begin: "\"\"\"", end: "\"\"\""),
                Mode(begin: "'''", end: "'''"),
                Mode(begin: "~S\"\"\"", end: "\"\"\"", contains: []),
                Mode(begin: "~S\"", end: "\"", contains: []),
                Mode(begin: "~S'''", end: "'''", contains: []),
                Mode(begin: "~S'", end: "'", contains: []),
                Mode(begin: "'", end: "'"),
                Mode(begin: "\"", end: "\""),
            ]
        )
        func declaration(scope: String, keywords words: String, end: String) -> Mode {
            Mode(
                scope: .name(scope),
                beginKeywords: words,
                end: .re(end),
                contains: [Mode(
                    scope: "title",
                    begin: .re(identifier),
                    relevance: 0,
                    endsParent: true
                )]
            )
        }
        let function = declaration(
            // The upstream match-nothing end is completed by the title's
            // `endsParent`. Explicit EOF recovery prevents a truncated
            // declaration from tripping the native zero-width loop fuse.
            scope: "function", keywords: "def defp defmacro defmacrop", end: #"\B\b|$"#
        )
        let typeDeclaration = declaration(
            scope: "class", keywords: "defimpl defmodule defprotocol defrecord", end: #"\bdo\b|$|;"#
        )
        let contains: [Mode] = [
            string,
            regexSigil,
            uppercaseSigil,
            lowercaseSigil,
            CommonModes.hashCommentMode,
            typeDeclaration,
            function,
            Mode(begin: "::"),
            Mode(
                scope: "symbol",
                begin: #":(?![\s:])"#,
                contains: [string, Mode(begin: .re(method))],
                relevance: 0
            ),
            Mode(scope: "symbol", begin: .re(identifier + ":(?!:)"), relevance: 0),
            Mode(scope: "title.class", begin: #"(\b[A-Z][a-zA-Z0-9_]+)"#, relevance: 0),
            number,
            Mode(scope: "variable", begin: #"(\$\W)|((\$|@@?)(\w+))"#),
        ]
        substitution.contains = contains
        return LanguageDefinition(
            name: "elixir",
            aliases: ["ex", "exs"],
            root: Mode(keywords: keywords, contains: contains)
        )
    }
}
