import Foundation

extension LanguageCatalog {
    /// Scala. Port of highlight.js `languages/scala.js`.
    public static let scala = LanguageDescriptor(name: "scala") {
        let annotation = Mode(scope: "meta", begin: "@[A-Za-z]+")

        // used in strings for escaping/interpolation/substitution
        let subst = Mode(
            scope: "subst",
            variants: [
                Mode(begin: #"\$[A-Za-z0-9_]+"#),
                Mode(begin: #"\$\{"#, end: #"\}"#),
            ]
        )

        let string = Mode(
            scope: "string",
            variants: [
                Mode(begin: "\"\"\"", end: "\"\"\""),
                Mode(
                    begin: "\"",
                    end: "\"",
                    illegal: ["\\n"],
                    contains: [CommonModes.backslashEscape]
                ),
                Mode(
                    begin: "[a-z]+\"",
                    end: "\"",
                    illegal: ["\\n"],
                    contains: [
                        CommonModes.backslashEscape,
                        subst,
                    ]
                ),
                Mode(
                    scope: "string",
                    begin: "[a-z]+\"\"\"",
                    end: "\"\"\"",
                    contains: [subst],
                    relevance: 10
                ),
            ]
        )

        let type = Mode(
            scope: "type",
            begin: "\\b[A-Z][A-Za-z0-9_]*",
            relevance: 0
        )

        let name = Mode(
            scope: "title",
            begin: #"[^0-9\n\t "'(),.`{}\[\]:;][^\n\t "'(),.`{}\[\]:;]+|[^0-9\n\t "'(),.`{}\[\]:;=]"#,
            relevance: 0
        )

        let classMode = Mode(
            scope: "class",
            beginKeywords: "class object trait type",
            end: #"[:={\[\n;]"#,
            contains: [
                CommonModes.cLineCommentMode,
                CommonModes.cBlockCommentMode,
                Mode(beginKeywords: "extends with", relevance: 10),
                Mode(
                    begin: #"\["#,
                    end: #"\]"#,
                    contains: [
                        type,
                        CommonModes.cLineCommentMode,
                        CommonModes.cBlockCommentMode,
                    ],
                    relevance: 0,
                    excludeBegin: true,
                    excludeEnd: true
                ),
                Mode(
                    scope: "params",
                    begin: #"\("#,
                    end: #"\)"#,
                    contains: [
                        type,
                        CommonModes.cLineCommentMode,
                        CommonModes.cBlockCommentMode,
                    ],
                    relevance: 0,
                    excludeBegin: true,
                    excludeEnd: true
                ),
                name,
            ],
            excludeEnd: true
        )

        let method = Mode(
            scope: "function",
            beginKeywords: "def",
            end: .re(RegexSource.lookahead(#"[:={\[(\n;]"#)),
            contains: [name]
        )

        let extensionMode = Mode(
            begin: [
                #"^\s*"#, // Is first token on the line
                "extension",
                #"\s+(?=[\[(])"#, // followed by at least one space and `[` or `(`
            ],
            beginScope: [2: "keyword"]
        )

        let end = Mode(
            begin: [
                #"^\s*"#, // Is first token on the line
                "end",
                #"\s+"#,
                // `extension` is the only marker that follows an `end`
                // that cannot be captured by another rule.
                #"(extension\b)?"#,
            ],
            beginScope: [2: "keyword", 4: "keyword"]
        )

        // TODO: use negative look-behind in future
        //       /(?<!\.)\binline(?=\s)/
        let inlineModes: [Mode] = [
            Mode(match: #"\.inline\b"#),
            Mode(begin: #"\binline(?=\s)"#, keywords: "inline"),
        ]

        let usingParamClause = Mode(
            begin: [
                #"\(\s*"#, // Opening `(` of a parameter or argument list
                "using",
                #"\s+(?!\))"#, // Spaces not followed by `)`
            ],
            beginScope: [2: "keyword"]
        )

        // glob all non-whitespace characters as a "string"
        // sourced from https://github.com/scala/docs.scala-lang/pull/2845
        let directiveValue = Mode(scope: "string", begin: #"\S+"#)

        // directives
        // sourced from https://github.com/scala/docs.scala-lang/pull/2845
        let usingDirective = Mode(
            begin: [
                "//>",
                #"\s+"#,
                "using",
                #"\s+"#,
                #"\S+"#,
            ],
            beginScope: [1: "comment", 3: "keyword", 5: "type"],
            end: "$",
            contains: [directiveValue]
        )

        return LanguageDefinition(
            name: "scala",
            root: Mode(
                keywords: [
                    "literal": "true false null",
                    "keyword": "type yield lazy override def with val var sealed abstract private trait object if then forSome for while do throw finally protected extends import final return else break new catch super class case package default try this match continue throws implicit export enum given transparent",
                ],
                contains: [
                    usingDirective,
                    CommonModes.cLineCommentMode,
                    CommonModes.cBlockCommentMode,
                    string,
                    type,
                    method,
                    classMode,
                    CommonModes.cNumberMode,
                    extensionMode,
                    end,
                ] + inlineModes + [
                    usingParamClause,
                    annotation,
                ]
            )
        )
    }
}
