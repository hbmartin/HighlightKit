import Foundation

extension LanguageCatalog {
    /// Python. Port of highlight.js `languages/python.js`.
    public static let python = LanguageDescriptor(name: "python", aliases: ["py", "gyp", "ipython"]) {
        let identRe = #"[\p{XID_Start}_]\p{XID_Continue}*"#
        let reservedWords = [
            "and",
            "as",
            "assert",
            "async",
            "await",
            "break",
            "case",
            "class",
            "continue",
            "def",
            "del",
            "elif",
            "else",
            "except",
            "finally",
            "for",
            "from",
            "global",
            "if",
            "import",
            "in",
            "is",
            "lambda",
            "match",
            "nonlocal|10",
            "not",
            "or",
            "pass",
            "raise",
            "return",
            "try",
            "while",
            "with",
            "yield",
        ]

        let builtIns = [
            "__import__",
            "abs",
            "all",
            "any",
            "ascii",
            "bin",
            "bool",
            "breakpoint",
            "bytearray",
            "bytes",
            "callable",
            "chr",
            "classmethod",
            "compile",
            "complex",
            "delattr",
            "dict",
            "dir",
            "divmod",
            "enumerate",
            "eval",
            "exec",
            "filter",
            "float",
            "format",
            "frozenset",
            "getattr",
            "globals",
            "hasattr",
            "hash",
            "help",
            "hex",
            "id",
            "input",
            "int",
            "isinstance",
            "issubclass",
            "iter",
            "len",
            "list",
            "locals",
            "map",
            "max",
            "memoryview",
            "min",
            "next",
            "object",
            "oct",
            "open",
            "ord",
            "pow",
            "print",
            "property",
            "range",
            "repr",
            "reversed",
            "round",
            "set",
            "setattr",
            "slice",
            "sorted",
            "staticmethod",
            "str",
            "sum",
            "super",
            "tuple",
            "type",
            "vars",
            "zip",
        ]

        let literals = [
            "__debug__",
            "Ellipsis",
            "False",
            "None",
            "NotImplemented",
            "True",
        ]

        // https://docs.python.org/3/library/typing.html
        let types = [
            "Any",
            "Callable",
            "Coroutine",
            "Dict",
            "List",
            "Literal",
            "Generic",
            "Optional",
            "Sequence",
            "Set",
            "Tuple",
            "Type",
            "Union",
        ]

        let keywords = Keywords(
            pattern: #"[A-Za-z]\w+|__\w+__"#,
            [
                "keyword": Keywords.Group(words: reservedWords),
                "built_in": Keywords.Group(words: builtIns),
                "literal": Keywords.Group(words: literals),
                "type": Keywords.Group(words: types),
            ]
        )

        let prompt = Mode(
            scope: "meta",
            begin: #"^(>>>|\.\.\.) "#
        )

        let subst = Mode(
            scope: "subst",
            begin: #"\{"#,
            end: #"\}"#,
            keywords: keywords,
            illegal: ["#"]
        )

        let literalBracket = Mode(
            begin: #"\{\{"#,
            relevance: 0
        )

        let string = Mode(
            scope: "string",
            contains: [CommonModes.backslashEscape],
            variants: [
                Mode(
                    begin: #"([uU]|[bB]|[rR]|[bB][rR]|[rR][bB])?'''"#,
                    end: "'''",
                    contains: [
                        CommonModes.backslashEscape,
                        prompt,
                    ],
                    relevance: 10
                ),
                Mode(
                    begin: #"([uU]|[bB]|[rR]|[bB][rR]|[rR][bB])?""""#,
                    end: #"""""#,
                    contains: [
                        CommonModes.backslashEscape,
                        prompt,
                    ],
                    relevance: 10
                ),
                Mode(
                    begin: #"([fF][rR]|[rR][fF]|[fF])'''"#,
                    end: "'''",
                    contains: [
                        CommonModes.backslashEscape,
                        prompt,
                        literalBracket,
                        subst,
                    ]
                ),
                Mode(
                    begin: #"([fF][rR]|[rR][fF]|[fF])""""#,
                    end: #"""""#,
                    contains: [
                        CommonModes.backslashEscape,
                        prompt,
                        literalBracket,
                        subst,
                    ]
                ),
                Mode(
                    begin: "([uU]|[rR])'",
                    end: "'",
                    relevance: 10
                ),
                Mode(
                    begin: "([uU]|[rR])\"",
                    end: "\"",
                    relevance: 10
                ),
                Mode(
                    begin: "([bB]|[bB][rR]|[rR][bB])'",
                    end: "'"
                ),
                Mode(
                    begin: "([bB]|[bB][rR]|[rR][bB])\"",
                    end: "\""
                ),
                Mode(
                    begin: "([fF][rR]|[rR][fF]|[fF])'",
                    end: "'",
                    contains: [
                        CommonModes.backslashEscape,
                        literalBracket,
                        subst,
                    ]
                ),
                Mode(
                    begin: "([fF][rR]|[rR][fF]|[fF])\"",
                    end: "\"",
                    contains: [
                        CommonModes.backslashEscape,
                        literalBracket,
                        subst,
                    ]
                ),
                CommonModes.aposStringMode,
                CommonModes.quoteStringMode,
            ]
        )

        // https://docs.python.org/3.9/reference/lexical_analysis.html#numeric-literals
        let digitpart = "[0-9](_?[0-9])*"
        let pointfloat = "(\\b(\(digitpart)))?\\.(\(digitpart))|\\b(\(digitpart))\\."
        // We deviate slightly, requiring a word boundary or a keyword
        // to avoid accidentally recognizing *prefixes* (e.g., `0` in `0x41` or `08` or `0__1`)
        let lookahead = "\\b|" + reservedWords.joined(separator: "|")
        let number = Mode(
            scope: "number",
            variants: [
                // exponentfloat, pointfloat — optionally imaginary
                Mode(begin: .re("(\\b(\(digitpart))|(\(pointfloat)))[eE][+-]?(\(digitpart))[jJ]?(?=\(lookahead))")),
                Mode(begin: .re("(\(pointfloat))[jJ]?")),

                // decinteger, bininteger, octinteger, hexinteger — optionally "long"/imaginary
                Mode(begin: .re("\\b([1-9](_?[0-9])*|0+(_?0)*)[lLjJ]?(?=\(lookahead))")),
                Mode(begin: .re("\\b0[bB](_?[01])+[lL]?(?=\(lookahead))")),
                Mode(begin: .re("\\b0[oO](_?[0-7])+[lL]?(?=\(lookahead))")),
                Mode(begin: .re("\\b0[xX](_?[0-9a-fA-F])+[lL]?(?=\(lookahead))")),

                // imagnumber (digitpart-based)
                Mode(begin: .re("\\b(\(digitpart))[jJ](?=\(lookahead))")),
            ],
            relevance: 0
        )

        let commentType = Mode(
            scope: "comment",
            begin: .re(RegexSource.lookahead("# type:")),
            end: "$",
            keywords: keywords,
            contains: [
                // prevent keywords from coloring `type`
                Mode(begin: "# type:"),
                // comment within a datatype comment includes no keywords
                Mode(
                    begin: "#",
                    end: #"\b\B"#,
                    endsWithParent: true
                ),
            ]
        )

        let params = Mode(
            scope: "params",
            variants: [
                // Exclude params in functions without params
                Mode(
                    scope: ScopeRef.none,
                    begin: #"\(\s*\)"#,
                    skip: true
                ),
                Mode(
                    begin: #"\("#,
                    end: #"\)"#,
                    keywords: keywords,
                    contains: [
                        Mode.selfReference,
                        prompt,
                        number,
                        string,
                        CommonModes.hashCommentMode,
                    ],
                    excludeBegin: true,
                    excludeEnd: true
                ),
            ]
        )
        subst.contains = [
            string,
            number,
            prompt,
        ]

        return LanguageDefinition(
            name: "python",
            aliases: ["py", "gyp", "ipython"],
            root: Mode(
                keywords: keywords,
                illegal: [#"(<\/|\?)|=>"#],
                contains: [
                    prompt,
                    number,
                    // very common convention
                    Mode(
                        scope: "variable.language",
                        match: #"\bself\b"#
                    ),
                    // eat "if" prior to string so that it won't accidentally be
                    // labeled as an f-string
                    Mode(
                        beginKeywords: "if",
                        relevance: 0
                    ),
                    Mode(scope: "keyword", match: #"\bor\b"#),
                    string,
                    commentType,
                    CommonModes.hashCommentMode,
                    Mode(
                        scope: [1: "keyword", 3: "title.function"],
                        match: [#"\bdef"#, #"\s+"#, identRe],
                        contains: [params]
                    ),
                    Mode(
                        scope: [
                            1: "keyword",
                            3: "title.class",
                            6: "title.class.inherited",
                        ],
                        variants: [
                            Mode(
                                match: [
                                    #"\bclass"#, #"\s+"#,
                                    identRe, #"\s*"#,
                                    #"\(\s*"#, identRe, #"\s*\)"#,
                                ]
                            ),
                            Mode(
                                match: [
                                    #"\bclass"#, #"\s+"#,
                                    identRe,
                                ]
                            ),
                        ]
                    ),
                    Mode(
                        scope: "meta",
                        begin: #"^[\t ]*@"#,
                        end: "(?=#)|$",
                        contains: [
                            number,
                            params,
                            string,
                        ]
                    ),
                ]
            )
        )
    }
}
