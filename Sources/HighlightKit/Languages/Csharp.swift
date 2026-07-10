import Foundation

extension LanguageCatalog {
    /// C#. Port of highlight.js `languages/csharp.js`.
    public static let csharp = LanguageDescriptor(name: "csharp", aliases: ["cs", "c#"]) {
        let builtInKeywords = [
            "bool",
            "byte",
            "char",
            "decimal",
            "delegate",
            "double",
            "dynamic",
            "enum",
            "float",
            "int",
            "long",
            "nint",
            "nuint",
            "object",
            "sbyte",
            "short",
            "string",
            "ulong",
            "uint",
            "ushort",
        ]
        let functionModifiers = [
            "public",
            "private",
            "protected",
            "static",
            "internal",
            "protected",
            "abstract",
            "async",
            "extern",
            "override",
            "unsafe",
            "virtual",
            "new",
            "sealed",
            "partial",
        ]
        let literalKeywords = [
            "default",
            "false",
            "null",
            "true",
        ]
        let normalKeywords = [
            "abstract",
            "as",
            "base",
            "break",
            "case",
            "catch",
            "class",
            "const",
            "continue",
            "do",
            "else",
            "event",
            "explicit",
            "extern",
            "finally",
            "fixed",
            "for",
            "foreach",
            "goto",
            "if",
            "implicit",
            "in",
            "interface",
            "internal",
            "is",
            "lock",
            "namespace",
            "new",
            "operator",
            "out",
            "override",
            "params",
            "private",
            "protected",
            "public",
            "readonly",
            "record",
            "ref",
            "return",
            "scoped",
            "sealed",
            "sizeof",
            "stackalloc",
            "static",
            "struct",
            "switch",
            "this",
            "throw",
            "try",
            "typeof",
            "unchecked",
            "unsafe",
            "using",
            "virtual",
            "void",
            "volatile",
            "while",
        ]
        let contextualKeywords = [
            "add",
            "alias",
            "and",
            "ascending",
            "args",
            "async",
            "await",
            "by",
            "descending",
            "dynamic",
            "equals",
            "file",
            "from",
            "get",
            "global",
            "group",
            "init",
            "into",
            "join",
            "let",
            "nameof",
            "not",
            "notnull",
            "on",
            "or",
            "orderby",
            "partial",
            "record",
            "remove",
            "required",
            "scoped",
            "select",
            "set",
            "unmanaged",
            "value|0",
            "var",
            "when",
            "where",
            "with",
            "yield",
        ]

        let keywords = Keywords([
            "keyword": Keywords.Group(words: normalKeywords + contextualKeywords),
            "built_in": Keywords.Group(words: builtInKeywords),
            "literal": Keywords.Group(words: literalKeywords),
        ])
        let titleMode: Mode = {
            let m = CommonModes.titleMode
            m.begin = #"[a-zA-Z](\.?\w)*"#
            return m
        }()
        let numbers = Mode(
            scope: "number",
            variants: [
                Mode(begin: #"\b(0b[01']+)"#),
                Mode(begin: #"(-?)\b([\d']+(\.[\d']*)?|\.[\d']+)(u|U|l|L|ul|UL|f|F|b|B)"#),
                Mode(begin: #"(-?)(\b0[xX][a-fA-F0-9']+|(\b[\d']+(\.[\d']*)?|\.[\d']+)([eE][-+]?[\d']+)?)"#),
            ],
            relevance: 0
        )
        let rawString = Mode(
            scope: "string",
            begin: #""""("*)(?!")(.|\n)*?"""\1"#,
            relevance: 1
        )
        let verbatimString = Mode(
            scope: "string",
            begin: "@\"",
            end: "\"",
            contains: [Mode(begin: "\"\"")]
        )
        let verbatimStringNoLF: Mode = {
            let m = Mode(
                scope: "string",
                begin: "@\"",
                end: "\"",
                contains: [Mode(begin: "\"\"")]
            )
            m.illegal = [#"\n"#]
            return m
        }()
        let subst = Mode(
            scope: "subst",
            begin: #"\{"#,
            end: #"\}"#,
            keywords: keywords
        )
        let substNoLF: Mode = {
            let m = Mode(
                scope: "subst",
                begin: #"\{"#,
                end: #"\}"#,
                keywords: keywords
            )
            m.illegal = [#"\n"#]
            return m
        }()
        let interpolatedString = Mode(
            scope: "string",
            begin: #"\$""#,
            end: "\"",
            illegal: [#"\n"#],
            contains: [
                Mode(begin: #"\{\{"#),
                Mode(begin: #"\}\}"#),
                CommonModes.backslashEscape,
                substNoLF,
            ]
        )
        let interpolatedVerbatimString = Mode(
            scope: "string",
            begin: #"\$@""#,
            end: "\"",
            contains: [
                Mode(begin: #"\{\{"#),
                Mode(begin: #"\}\}"#),
                Mode(begin: "\"\""),
                subst,
            ]
        )
        let interpolatedVerbatimStringNoLF = Mode(
            scope: "string",
            begin: #"\$@""#,
            end: "\"",
            illegal: [#"\n"#],
            contains: [
                Mode(begin: #"\{\{"#),
                Mode(begin: #"\}\}"#),
                Mode(begin: "\"\""),
                substNoLF,
            ]
        )
        subst.contains = [
            interpolatedVerbatimString,
            interpolatedString,
            verbatimString,
            CommonModes.aposStringMode,
            CommonModes.quoteStringMode,
            numbers,
            CommonModes.cBlockCommentMode,
        ]
        substNoLF.contains = [
            interpolatedVerbatimStringNoLF,
            interpolatedString,
            verbatimStringNoLF,
            CommonModes.aposStringMode,
            CommonModes.quoteStringMode,
            numbers,
            {
                let m = CommonModes.cBlockCommentMode
                m.illegal = [#"\n"#]
                return m
            }(),
        ]
        let string = Mode(variants: [
            rawString,
            interpolatedVerbatimString,
            interpolatedString,
            verbatimString,
            CommonModes.aposStringMode,
            CommonModes.quoteStringMode,
        ])

        let genericModifier = Mode(
            begin: "<",
            end: ">",
            contains: [
                Mode(beginKeywords: "in out"),
                titleMode,
            ]
        )
        let typeIdentRe = CommonModes.identRe
            + "(<" + CommonModes.identRe + #"(\s*,\s*"# + CommonModes.identRe + #")*>)?(\[\])?"#
        let atIdentifier = Mode(
            // prevents expressions like `@class` from incorrect flagging
            // `class` as a keyword
            begin: .re("@" + CommonModes.identRe),
            relevance: 0
        )

        return LanguageDefinition(
            name: "csharp",
            aliases: ["cs", "c#"],
            root: Mode(
                keywords: keywords,
                illegal: ["::"],
                contains: [
                    CommonModes.comment("///", "$") { m in
                        m.returnBegin = true
                        m.contains = [
                            Mode(
                                scope: "doctag",
                                variants: [
                                    Mode(begin: "///", relevance: 0),
                                    Mode(begin: "<!--|-->"),
                                    Mode(begin: "</?", end: ">"),
                                ]
                            ),
                        ]
                    },
                    CommonModes.cLineCommentMode,
                    CommonModes.cBlockCommentMode,
                    Mode(
                        scope: "meta",
                        begin: "#",
                        end: "$",
                        keywords: [
                            "keyword": "if else elif endif define undef warning error line region endregion pragma checksum",
                        ]
                    ),
                    string,
                    numbers,
                    Mode(
                        beginKeywords: "class interface",
                        end: "[{;=]",
                        illegal: [#"[^\s:,]"#],
                        contains: [
                            Mode(beginKeywords: "where class"),
                            titleMode,
                            genericModifier,
                            CommonModes.cLineCommentMode,
                            CommonModes.cBlockCommentMode,
                        ],
                        relevance: 0
                    ),
                    Mode(
                        beginKeywords: "namespace",
                        end: "[{;=]",
                        illegal: [#"[^\s:]"#],
                        contains: [
                            titleMode,
                            CommonModes.cLineCommentMode,
                            CommonModes.cBlockCommentMode,
                        ],
                        relevance: 0
                    ),
                    Mode(
                        beginKeywords: "record",
                        end: "[{;=]",
                        illegal: [#"[^\s:]"#],
                        contains: [
                            titleMode,
                            genericModifier,
                            CommonModes.cLineCommentMode,
                            CommonModes.cBlockCommentMode,
                        ],
                        relevance: 0
                    ),
                    Mode(
                        // [Attributes("")]
                        scope: "meta",
                        begin: #"^\s*\[(?=[\w])"#,
                        end: #"\]"#,
                        contains: [
                            Mode(scope: "string", begin: "\"", end: "\""),
                        ],
                        excludeBegin: true,
                        excludeEnd: true
                    ),
                    Mode(
                        // Expression keywords prevent 'keyword Name(...)' from being
                        // recognized as a function definition
                        beginKeywords: "new return throw await else",
                        relevance: 0
                    ),
                    Mode(
                        scope: "function",
                        begin: .re("(" + typeIdentRe + #"\s+)+"# + CommonModes.identRe + #"\s*(<[^=]+>\s*)?\("#),
                        end: #"\s*[{;=]"#,
                        keywords: keywords,
                        contains: [
                            // prevents these from being highlighted `title`
                            Mode(
                                beginKeywords: functionModifiers.joined(separator: " "),
                                relevance: 0
                            ),
                            Mode(
                                begin: .re(CommonModes.identRe + #"\s*(<[^=]+>\s*)?\("#),
                                contains: [
                                    CommonModes.titleMode,
                                    genericModifier,
                                ],
                                relevance: 0,
                                returnBegin: true
                            ),
                            Mode(match: #"\(\)"#),
                            Mode(
                                scope: "params",
                                begin: #"\("#,
                                end: #"\)"#,
                                keywords: keywords,
                                contains: [
                                    string,
                                    numbers,
                                    CommonModes.cBlockCommentMode,
                                ],
                                relevance: 0,
                                excludeBegin: true,
                                excludeEnd: true
                            ),
                            CommonModes.cLineCommentMode,
                            CommonModes.cBlockCommentMode,
                        ],
                        excludeEnd: true,
                        returnBegin: true
                    ),
                    atIdentifier,
                ]
            )
        )
    }
}
