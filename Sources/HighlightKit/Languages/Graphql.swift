import Foundation

extension LanguageCatalog {
    /// GraphQL. Port of highlight.js `languages/graphql.js` at 08cb242.
    public static let graphql = LanguageDescriptor(name: "graphql", aliases: ["gql"]) {
        let name = #"[_A-Za-z][_0-9A-Za-z]*"#
        let keywords = Keywords([
            "keyword": Keywords.Group(words: [
                "query", "mutation", "subscription", "type", "input", "schema",
                "directive", "interface", "union", "scalar", "fragment", "enum", "on",
            ]),
            "literal": Keywords.Group(words: ["true", "false", "null"]),
        ])
        return LanguageDefinition(
            name: "graphql",
            aliases: ["gql"],
            caseInsensitive: true,
            root: Mode(
                keywords: keywords,
                illegal: [#"[;<']"#, "BEGIN"],
                contains: [
                    CommonModes.hashCommentMode,
                    CommonModes.quoteStringMode,
                    CommonModes.numberMode,
                    Mode(scope: "punctuation", match: #"[.]{3}"#, relevance: 0),
                    Mode(scope: "punctuation", begin: #"[!():=\[\]{}|]"#, relevance: 0),
                    Mode(
                        scope: "variable",
                        begin: #"\$"#,
                        end: #"\W"#,
                        relevance: 0,
                        excludeEnd: true
                    ),
                    Mode(scope: "meta", match: #"@\w+"#, excludeEnd: true),
                    Mode(
                        scope: "symbol",
                        begin: .re(name + RegexSource.lookahead(#"\s*:"#)),
                        relevance: 0
                    ),
                ]
            )
        )
    }
}
