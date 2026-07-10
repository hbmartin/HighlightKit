import Foundation

extension LanguageCatalog {
    /// Java. Port of highlight.js `languages/java.js`.
    public static let java = LanguageDescriptor(name: "java", aliases: ["jsp"]) {
        /// Allows recursive regex expressions to a given depth
        ///
        /// ie: `recurRegex("(abc~~~)", "~~~", 2)` becomes `(abc(abc(abc)))`
        func recurRegex(_ re: String, _ substitution: String, _ depth: Int) -> String {
            if depth == -1 { return "" }
            return re.replacingOccurrences(of: substitution, with: recurRegex(re, substitution, depth - 1))
        }

        let javaIdentRe = "[\u{00C0}-\u{02B8}a-zA-Z_$][\u{00C0}-\u{02B8}a-zA-Z_$0-9]*"
        let genericIdentRe = javaIdentRe
            + recurRegex("(?:<" + javaIdentRe + "~~~(?:\\s*,\\s*" + javaIdentRe + "~~~)*>)?", "~~~", 2)
        let mainKeywords = [
            "synchronized",
            "abstract",
            "private",
            "var",
            "static",
            "if",
            "const ",
            "for",
            "while",
            "strictfp",
            "finally",
            "protected",
            "import",
            "native",
            "final",
            "void",
            "enum",
            "else",
            "break",
            "transient",
            "catch",
            "instanceof",
            "volatile",
            "case",
            "assert",
            "package",
            "default",
            "public",
            "try",
            "switch",
            "continue",
            "throws",
            "protected",
            "public",
            "private",
            "module",
            "requires",
            "exports",
            "do",
            "sealed",
            "yield",
            "permits",
            "goto",
            "when",
        ]

        let builtIns = [
            "super",
            "this",
        ]

        let literals = [
            "false",
            "true",
            "null",
        ]

        let types = [
            "char",
            "boolean",
            "long",
            "float",
            "int",
            "byte",
            "short",
            "double",
        ]

        let keywords = Keywords([
            "keyword": Keywords.Group(words: mainKeywords),
            "literal": Keywords.Group(words: literals),
            "type": Keywords.Group(words: types),
            "built_in": Keywords.Group(words: builtIns),
        ])

        let annotation = Mode(
            scope: "meta",
            begin: .re("@" + javaIdentRe),
            contains: [
                Mode(
                    begin: #"\("#,
                    end: #"\)"#,
                    contains: [Mode.selfReference] // allow nested () inside our annotation
                ),
            ]
        )
        let params = Mode(
            scope: "params",
            begin: #"\("#,
            end: #"\)"#,
            keywords: keywords,
            contains: [CommonModes.cBlockCommentMode],
            relevance: 0,
            endsParent: true
        )

        return LanguageDefinition(
            name: "java",
            aliases: ["jsp"],
            root: Mode(
                keywords: keywords,
                illegal: [#"<\/|#"#],
                contains: [
                    CommonModes.comment("/\\*\\*", "\\*/") { mode in
                        mode.relevance = 0
                        mode.contains = [
                            // eat up @'s in emails to prevent them to be recognized as doctags
                            Mode(begin: #"\w+@"#, relevance: 0),
                            Mode(scope: "doctag", begin: "@[A-Za-z]+"),
                        ]
                    },
                    // relevance boost
                    Mode(
                        begin: #"import java\.[a-z]+\."#,
                        keywords: "import",
                        relevance: 2
                    ),
                    CommonModes.cLineCommentMode,
                    CommonModes.cBlockCommentMode,
                    Mode(
                        scope: "string",
                        begin: "\"\"\"",
                        end: "\"\"\"",
                        contains: [CommonModes.backslashEscape]
                    ),
                    CommonModes.aposStringMode,
                    CommonModes.quoteStringMode,
                    Mode(
                        scope: [1: "keyword", 3: "title.class"],
                        match: [#"\b(?:class|interface|enum|extends|implements|new)"#, #"\s+"#, javaIdentRe]
                    ),
                    // Exceptions for hyphenated keywords
                    Mode(
                        scope: "keyword",
                        match: "non-sealed"
                    ),
                    Mode(
                        scope: [1: "type", 3: "variable", 5: "operator"],
                        begin: [
                            RegexSource.concat("(?!else)", javaIdentRe),
                            #"\s+"#,
                            javaIdentRe,
                            #"\s+"#,
                            "=(?!=)",
                        ]
                    ),
                    Mode(
                        scope: [1: "keyword", 3: "title.class"],
                        begin: ["record", #"\s+"#, javaIdentRe],
                        contains: [
                            params,
                            CommonModes.cLineCommentMode,
                            CommonModes.cBlockCommentMode,
                        ]
                    ),
                    // Expression keywords prevent 'keyword Name(...)' from being
                    // recognized as a function definition
                    Mode(
                        beginKeywords: "new throw return else",
                        relevance: 0
                    ),
                    Mode(
                        scope: [2: "title.function"],
                        begin: [
                            "(?:" + genericIdentRe + "\\s+)",
                            CommonModes.underscoreIdentRe,
                            #"\s*(?=\()"#,
                        ],
                        keywords: keywords,
                        contains: [
                            Mode(
                                scope: "params",
                                begin: #"\("#,
                                end: #"\)"#,
                                keywords: keywords,
                                contains: [
                                    annotation,
                                    CommonModes.aposStringMode,
                                    CommonModes.quoteStringMode,
                                    JavaShared.numeric,
                                    CommonModes.cBlockCommentMode,
                                ],
                                relevance: 0
                            ),
                            CommonModes.cLineCommentMode,
                            CommonModes.cBlockCommentMode,
                        ]
                    ),
                    JavaShared.numeric,
                    annotation,
                ]
            )
        )
    }
}
