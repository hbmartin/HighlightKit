import Foundation

extension LanguageCatalog {
    /// Kotlin. Port of highlight.js `languages/kotlin.js`.
    public static let kotlin = LanguageDescriptor(name: "kotlin", aliases: ["kt", "kts", "ktm", "ktx"]) {
        let keywords = Keywords([
            "keyword": Keywords.Group(stringLiteral:
                "abstract as val var vararg get set class object open private protected public noinline "
                + "crossinline dynamic final enum if else do while for when throw try catch finally "
                + "import package is in fun override companion reified inline lateinit init "
                + "interface annotation data sealed internal infix operator out by constructor super "
                + "tailrec where const inner suspend typealias external expect actual"),
            "built_in": "Byte Short Char Int Long Boolean Float Double Void Unit Nothing",
            "literal": "true false null",
        ])
        let keywordsWithLabel = Mode(
            scope: "keyword",
            begin: #"\b(break|continue|return|this)\b"#,
            starts: Mode(contains: [
                Mode(scope: "symbol", begin: #"@\w+"#),
            ])
        )
        let label = Mode(
            scope: "symbol",
            begin: .re(CommonModes.underscoreIdentRe + "@")
        )

        // for string templates
        let subst = Mode(
            scope: "subst",
            begin: #"\$\{"#,
            end: #"\}"#,
            contains: [CommonModes.cNumberMode]
        )
        let variable = Mode(
            scope: "variable",
            begin: .re("\\$" + CommonModes.underscoreIdentRe)
        )
        let string = Mode(
            scope: "string",
            variants: [
                Mode(
                    begin: "\"\"\"",
                    end: "\"\"\"(?=[^\"])",
                    contains: [
                        variable,
                        subst,
                    ]
                ),
                // Can't use built-in modes easily, as we want to use STRING in the meta
                // context as 'meta-string' and there's no syntax to remove explicitly set
                // classNames in built-in modes.
                Mode(
                    begin: "'",
                    end: "'",
                    illegal: [#"\n"#],
                    contains: [CommonModes.backslashEscape]
                ),
                Mode(
                    begin: "\"",
                    end: "\"",
                    illegal: [#"\n"#],
                    contains: [
                        CommonModes.backslashEscape,
                        variable,
                        subst,
                    ]
                ),
            ]
        )
        subst.contains = (subst.contains ?? []) + [string]

        let annotationUseSite = Mode(
            scope: "meta",
            begin: .re("@(?:file|property|field|get|set|receiver|param|setparam|delegate)\\s*:(?:\\s*"
                + CommonModes.underscoreIdentRe + ")?")
        )
        let annotation = Mode(
            scope: "meta",
            begin: .re("@" + CommonModes.underscoreIdentRe),
            contains: [
                Mode(
                    begin: #"\("#,
                    end: #"\)"#,
                    contains: [
                        string.copied { $0.scope = "string" },
                        Mode.selfReference,
                    ]
                ),
            ]
        )

        // https://kotlinlang.org/docs/reference/whatsnew11.html#underscores-in-numeric-literals
        // According to the doc above, the number mode of kotlin is the same as java 8,
        // so the code below is copied from java.js
        let kotlinNumberMode = JavaShared.numeric
        let kotlinNestedComment = CommonModes.comment("/\\*", "\\*/") { mode in
            mode.contains = [CommonModes.cBlockCommentMode]
        }
        let kotlinParenType = Mode(variants: [
            Mode(
                scope: "type",
                begin: .re(CommonModes.underscoreIdentRe)
            ),
            Mode(
                begin: #"\("#,
                end: #"\)"#,
                contains: [] // defined later
            ),
        ])
        // upstream aliases KOTLIN_PAREN_TYPE2 to the same object, so the net
        // effect of its two assignments is a self-referential cycle.
        kotlinParenType.variants![1].contains = [kotlinParenType]

        return LanguageDefinition(
            name: "kotlin",
            aliases: [
                "kt",
                "kts",
                "ktm",
                "ktx",
            ],
            root: Mode(
                keywords: keywords,
                contains: [
                    CommonModes.comment("/\\*\\*", "\\*/") { mode in
                        mode.relevance = 0
                        mode.contains = [
                            Mode(scope: "doctag", begin: "@[A-Za-z]+"),
                        ]
                    },
                    CommonModes.cLineCommentMode,
                    kotlinNestedComment,
                    keywordsWithLabel,
                    label,
                    annotationUseSite,
                    annotation,
                    Mode(
                        scope: "function",
                        beginKeywords: "fun",
                        end: "[(]|$",
                        keywords: keywords,
                        contains: [
                            Mode(
                                begin: .re(CommonModes.underscoreIdentRe + "\\s*\\("),
                                contains: [CommonModes.underscoreTitleMode],
                                relevance: 0,
                                returnBegin: true
                            ),
                            Mode(
                                scope: "type",
                                begin: "<",
                                end: ">",
                                keywords: "reified",
                                relevance: 0
                            ),
                            Mode(
                                scope: "params",
                                begin: #"\("#,
                                end: #"\)"#,
                                keywords: keywords,
                                contains: [
                                    Mode(
                                        begin: ":",
                                        end: #"[=,\/]"#,
                                        contains: [
                                            kotlinParenType,
                                            CommonModes.cLineCommentMode,
                                            kotlinNestedComment,
                                        ],
                                        relevance: 0,
                                        endsWithParent: true
                                    ),
                                    CommonModes.cLineCommentMode,
                                    kotlinNestedComment,
                                    annotationUseSite,
                                    annotation,
                                    string,
                                    CommonModes.cNumberMode,
                                ],
                                relevance: 0,
                                endsParent: true
                            ),
                            kotlinNestedComment,
                        ],
                        relevance: 5,
                        excludeEnd: true,
                        returnBegin: true
                    ),
                    Mode(
                        begin: [
                            "class|interface|trait",
                            #"\s+"#,
                            CommonModes.underscoreIdentRe,
                        ],
                        beginScope: [3: "title.class"],
                        end: #"[:\{(]|$"#,
                        keywords: "class interface trait",
                        illegal: ["extends implements"],
                        contains: [
                            Mode(beginKeywords: "public protected internal private constructor"),
                            CommonModes.underscoreTitleMode,
                            Mode(
                                scope: "type",
                                begin: "<",
                                end: ">",
                                relevance: 0,
                                excludeBegin: true,
                                excludeEnd: true
                            ),
                            Mode(
                                scope: "type",
                                begin: #"[,:]\s*"#,
                                end: #"[<\(,){\s]|$"#,
                                excludeBegin: true,
                                returnEnd: true
                            ),
                            annotationUseSite,
                            annotation,
                        ],
                        excludeEnd: true
                    ),
                    string,
                    Mode(
                        scope: "meta",
                        begin: "^#!/usr/bin/env",
                        end: "$",
                        illegal: ["\n"]
                    ),
                    kotlinNumberMode,
                ]
            )
        )
    }
}
