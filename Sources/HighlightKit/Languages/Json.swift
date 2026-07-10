import Foundation

extension LanguageCatalog {
    /// JSON (JavaScript Object Notation).
    /// Port of highlight.js `languages/json.js`.
    public static let json = LanguageDescriptor(name: "json", aliases: ["jsonc"]) {
        let attribute = Mode(
            scope: "attr",
            begin: #""(\\.|[^\\"\r\n])*"(?=\s*:)"#,
            relevance: 1.01
        )
        // Note: `[` is escaped inside the class — ICU (unlike JavaScript)
        // parses an unescaped `[` there as a nested character class.
        let punctuation = Mode(
            scope: "punctuation",
            match: #"[{}\[\],:]"#,
            relevance: 0
        )
        let literals = "true false null"
        // NOTE: normally we would rely on `keywords` for this but using a
        // mode here allows us to use the very tight `illegal: \S` rule
        // later to flag any other character as illegal, greatly improving
        // detection since all sorts of text looks vaguely like JSON.
        let literalsMode = Mode(
            scope: "literal",
            beginKeywords: literals
        )

        return LanguageDefinition(
            name: "json",
            aliases: ["jsonc"],
            root: Mode(
                keywords: ["literal": "true false null"],
                illegal: [#"\S"#],
                contains: [
                    attribute,
                    punctuation,
                    CommonModes.quoteStringMode,
                    literalsMode,
                    CommonModes.cNumberMode,
                    CommonModes.cLineCommentMode,
                    CommonModes.cBlockCommentMode,
                ]
            )
        )
    }
}
