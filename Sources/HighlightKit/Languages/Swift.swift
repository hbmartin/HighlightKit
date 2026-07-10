import Foundation

extension LanguageCatalog {
    /// Swift. Port of highlight.js `languages/swift.js`.
    public static let swift = LanguageDescriptor(name: "swift") {
        let whitespace = Mode(match: #"\s+"#, relevance: 0)
        // https://docs.swift.org/swift-book/ReferenceManual/LexicalStructure.html#ID411
        let blockComment = CommonModes.comment(#"/\*"#, #"\*/"#) { mode in
            mode.contains = [Mode.selfReference]
        }
        let comments = [
            CommonModes.cLineCommentMode,
            blockComment,
        ]

        // https://docs.swift.org/swift-book/ReferenceManual/LexicalStructure.html#ID413
        // https://docs.swift.org/swift-book/ReferenceManual/zzSummaryOfTheGrammar.html
        let dotKeyword = Mode(
            scope: [2: "keyword"],
            match: [
                #"\."#,
                RegexSource.either(KwsSwift.dotKeywords + KwsSwift.optionalDotKeywords),
            ]
        )
        let keywordGuard = Mode(
            // Consume .keyword to prevent highlighting properties and methods as keywords.
            match: .re(#"\."# + RegexSource.either(KwsSwift.keywords)),
            relevance: 0
        )
        let plainKeywords = KwsSwift.plainKeywords
            + ["_|0"] // seems common, so 0 relevance
        let keyword = Mode(variants: [
            Mode(
                scope: "keyword",
                match: .re(KwsSwift.regexKeywordPattern)
            ),
        ])
        // find all the regular keywords
        let keywords = Keywords(
            pattern: RegexSource.either(
                #"\b\w+"#, // regular keywords
                #"#\w+"# // number keywords
            ),
            [
                "keyword": Keywords.Group(words: plainKeywords + KwsSwift.numberSignKeywords),
                "literal": Keywords.Group(words: KwsSwift.literals),
            ]
        )
        let keywordModes = [
            dotKeyword,
            keywordGuard,
            keyword,
        ]

        // https://github.com/apple/swift/tree/main/stdlib/public/core
        let builtInGuard = Mode(
            // Consume .built_in to prevent highlighting properties and methods.
            match: .re(#"\."# + RegexSource.either(KwsSwift.builtIns)),
            relevance: 0
        )
        let builtIn = Mode(
            scope: "built_in",
            match: .re(KwsSwift.builtInCallPattern)
        )
        let builtIns = [
            builtInGuard,
            builtIn,
        ]

        // https://docs.swift.org/swift-book/ReferenceManual/LexicalStructure.html#ID418
        let operatorGuard = Mode(
            // Prevent -> from being highlighting as an operator.
            match: "->",
            relevance: 0
        )
        let operatorMode = Mode(
            scope: "operator",
            variants: [
                Mode(match: .re(KwsSwift.operator)),
                // dot-operator: only operators that start with a dot are allowed to use dots as
                // characters (..., ...<, .*, etc). So there rule here is: a dot followed by one or more
                // characters that may also include dots.
                Mode(match: .re(#"\.(\.|"# + KwsSwift.operatorCharacter + ")+")),
            ],
            relevance: 0
        )
        let operators = [
            operatorGuard,
            operatorMode,
        ]

        // https://docs.swift.org/swift-book/ReferenceManual/LexicalStructure.html#grammar_numeric-literal
        // TODO: Update for leading `-` after lookbehind is supported everywhere
        let decimalDigits = "([0-9]_*)+"
        let hexDigits = "([0-9a-fA-F]_*)+"
        let number = Mode(
            scope: "number",
            variants: [
                // decimal floating-point-literal (subsumes decimal-literal)
                Mode(match: .re("\\b(\(decimalDigits))(\\.(\(decimalDigits)))?" + "([eE][+-]?(\(decimalDigits)))?\\b")),
                // hexadecimal floating-point-literal (subsumes hexadecimal-literal)
                Mode(match: .re("\\b0x(\(hexDigits))(\\.(\(hexDigits)))?" + "([pP][+-]?(\(decimalDigits)))?\\b")),
                // octal-literal
                Mode(match: #"\b0o([0-7]_*)+\b"#),
                // binary-literal
                Mode(match: #"\b0b([01]_*)+\b"#),
            ],
            relevance: 0
        )

        // https://docs.swift.org/swift-book/ReferenceManual/LexicalStructure.html#grammar_string-literal
        func escapedCharacter(_ rawDelimiter: String = "") -> Mode {
            Mode(
                scope: "subst",
                variants: [
                    Mode(match: .re(#"\\"# + rawDelimiter + #"[0\\tnr"']"#)),
                    Mode(match: .re(#"\\"# + rawDelimiter + #"u\{[0-9a-fA-F]{1,8}\}"#)),
                ]
            )
        }
        func escapedNewline(_ rawDelimiter: String = "") -> Mode {
            Mode(
                scope: "subst",
                match: .re(#"\\"# + rawDelimiter + #"[\t ]*(?:[\r\n]|\r\n)"#)
            )
        }
        func interpolation(_ rawDelimiter: String = "") -> Mode {
            Mode(
                scope: "subst",
                begin: .re(#"\\"# + rawDelimiter + #"\("#),
                end: #"\)"#,
                label: "interpol"
            )
        }
        func multilineString(_ rawDelimiter: String = "") -> Mode {
            Mode(
                begin: .re(rawDelimiter + "\"\"\""),
                end: .re("\"\"\"" + rawDelimiter),
                contains: [
                    escapedCharacter(rawDelimiter),
                    escapedNewline(rawDelimiter),
                    interpolation(rawDelimiter),
                ]
            )
        }
        func singleLineString(_ rawDelimiter: String = "") -> Mode {
            Mode(
                begin: .re(rawDelimiter + "\""),
                end: .re("\"" + rawDelimiter),
                contains: [
                    escapedCharacter(rawDelimiter),
                    interpolation(rawDelimiter),
                ]
            )
        }
        let string = Mode(
            scope: "string",
            variants: [
                multilineString(),
                multilineString("#"),
                multilineString("##"),
                multilineString("###"),
                singleLineString(),
                singleLineString("#"),
                singleLineString("##"),
                singleLineString("###"),
            ]
        )

        let backslashEscape = CommonModes.backslashEscape
        let regexpContents: [Mode] = [
            backslashEscape,
            Mode(
                begin: #"\["#,
                end: #"\]"#,
                contains: [backslashEscape],
                relevance: 0
            ),
        ]

        let bareRegexpLiteral = Mode(
            begin: #"\/[^\s](?=[^/\n]*\/)"#,
            end: #"\/"#,
            contains: regexpContents
        )

        func extendedRegexpLiteral(_ rawDelimiter: String) -> Mode {
            let begin = rawDelimiter + #"\/"#
            let end = #"\/"# + rawDelimiter
            return Mode(
                begin: .re(begin),
                end: .re(end),
                contains: regexpContents + [
                    Mode(
                        scope: "comment",
                        begin: .re("#(?!.*\(end))"),
                        end: "$"
                    ),
                ]
            )
        }

        // https://docs.swift.org/swift-book/documentation/the-swift-programming-language/lexicalstructure/#Regular-Expression-Literals
        let regexp = Mode(
            scope: "regexp",
            variants: [
                extendedRegexpLiteral("###"),
                extendedRegexpLiteral("##"),
                extendedRegexpLiteral("#"),
                bareRegexpLiteral,
            ]
        )

        // https://docs.swift.org/swift-book/ReferenceManual/LexicalStructure.html#ID412
        let quotedIdentifierMatch = "`" + KwsSwift.identifier + "`"
        let quotedIdentifier = Mode(match: .re(quotedIdentifierMatch))
        let implicitParameter = Mode(
            scope: "variable",
            match: #"\$\d+"#
        )
        let propertyWrapperProjection = Mode(
            scope: "variable",
            match: .re(#"\$"# + KwsSwift.identifierCharacter + "+")
        )
        let identifiers = [
            quotedIdentifier,
            implicitParameter,
            propertyWrapperProjection,
        ]

        // https://docs.swift.org/swift-book/ReferenceManual/Attributes.html
        let availableAttribute = Mode(
            scope: "keyword",
            match: "(@|#(un)?)available",
            starts: Mode(contains: [
                Mode(
                    begin: #"\("#,
                    end: #"\)"#,
                    keywords: Keywords(keyword: Keywords.Group(words: KwsSwift.availabilityKeywords)),
                    contains: operators + [
                        number,
                        string,
                    ]
                ),
            ])
        )

        let keywordAttribute = Mode(
            scope: "keyword",
            match: .re(
                "@" + RegexSource.either(KwsSwift.keywordAttributes)
                    + RegexSource.lookahead(RegexSource.either(#"\("#, #"\s+"#))
            )
        )

        let userDefinedAttribute = Mode(
            scope: "meta",
            match: .re("@" + KwsSwift.identifier)
        )

        let attributes = [
            availableAttribute,
            keywordAttribute,
            userDefinedAttribute,
        ]

        // https://docs.swift.org/swift-book/ReferenceManual/Types.html
        let type = Mode(
            match: .re(RegexSource.lookahead(#"\b[A-Z]"#)),
            contains: [
                // Common Apple frameworks, for relevance boost
                Mode(
                    scope: "type",
                    match: .re("(AV|CA|CF|CG|CI|CL|CM|CN|CT|MK|MP|MTK|MTL|NS|SCN|SK|UI|WK|XC)" + KwsSwift.identifierCharacter + "+")
                ),
                // Type identifier
                Mode(
                    scope: "type",
                    match: .re(KwsSwift.typeIdentifier),
                    relevance: 0
                ),
                // Optional type
                Mode(match: "[?!]+", relevance: 0),
                // Variadic parameter
                Mode(match: #"\.\.\."#, relevance: 0),
                // Protocol composition
                Mode(
                    match: .re(KwsSwift.protocolCompositionPattern),
                    relevance: 0
                ),
            ],
            relevance: 0
        )
        let genericArguments = Mode(
            begin: "<",
            end: ">",
            keywords: keywords,
            contains: comments + keywordModes + attributes + [
                operatorGuard,
                type,
            ]
        )
        type.contains?.append(genericArguments)

        // https://docs.swift.org/swift-book/ReferenceManual/Expressions.html#ID552
        // Prevents element names from being highlighted as keywords.
        let tupleElementName = Mode(
            match: .re(KwsSwift.identifierWithColon),
            keywords: "_|0",
            relevance: 0
        )
        // Matches tuples as well as the parameter list of a function type.
        let tuple = Mode(
            begin: #"\("#,
            end: #"\)"#,
            keywords: keywords,
            contains: [
                Mode.selfReference,
                tupleElementName,
            ] + comments + [
                regexp,
            ] + keywordModes + builtIns + operators + [
                number,
                string,
            ] + identifiers + attributes + [
                type,
            ],
            relevance: 0
        )

        let genericParameters = Mode(
            begin: "<",
            end: ">",
            keywords: "repeat each",
            contains: comments + [type]
        )
        let functionParameterName = Mode(
            begin: .re(KwsSwift.functionParameterNameLookahead),
            end: ":",
            contains: [
                Mode(scope: "keyword", match: #"\b_\b"#),
                Mode(scope: "params", match: .re(KwsSwift.identifier)),
            ],
            relevance: 0
        )
        let functionParameters = Mode(
            begin: #"\("#,
            end: #"\)"#,
            keywords: keywords,
            illegal: [#"["']"#],
            contains: [
                functionParameterName,
            ] + comments + keywordModes + operators + [
                number,
                string,
            ] + attributes + [
                type,
                tuple,
            ],
            endsParent: true
        )
        // https://docs.swift.org/swift-book/ReferenceManual/Declarations.html#ID362
        // https://docs.swift.org/swift-book/documentation/the-swift-programming-language/declarations/#Macro-Declaration
        let functionOrMacro = Mode(
            scope: [1: "keyword", 3: "title.function"],
            match: [
                "(func|macro)",
                #"\s+"#,
                RegexSource.either(quotedIdentifierMatch, KwsSwift.identifier, KwsSwift.operator),
            ],
            illegal: [#"\["#, "%"],
            contains: [
                genericParameters,
                functionParameters,
                whitespace,
            ]
        )

        // https://docs.swift.org/swift-book/ReferenceManual/Declarations.html#ID375
        // https://docs.swift.org/swift-book/ReferenceManual/Declarations.html#ID379
        let initSubscript = Mode(
            scope: [1: "keyword"],
            match: [
                #"\b(?:subscript|init[?!]?)"#,
                #"\s*(?=[<(])"#,
            ],
            illegal: [#"\[|%"#],
            contains: [
                genericParameters,
                functionParameters,
                whitespace,
            ]
        )
        // https://docs.swift.org/swift-book/ReferenceManual/Declarations.html#ID380
        let operatorDeclaration = Mode(
            scope: [1: "keyword", 3: "title"],
            match: [
                "operator",
                #"\s+"#,
                KwsSwift.operator,
            ]
        )

        // https://docs.swift.org/swift-book/ReferenceManual/Declarations.html#ID550
        let precedencegroupDeclaration = Mode(
            scope: [1: "keyword", 3: "title"],
            begin: [
                "precedencegroup",
                #"\s+"#,
                KwsSwift.typeIdentifier,
            ],
            // JS `/}/` — ICU requires the brace to be escaped.
            end: #"\}"#,
            keywords: Keywords(keyword: Keywords.Group(words: KwsSwift.precedencegroupKeywords + KwsSwift.literals)),
            contains: [type]
        )

        let classFuncDeclaration = Mode(
            scope: [1: "keyword", 3: "keyword", 5: "title.function"],
            match: [
                #"class\b"#,
                #"\s+"#,
                #"func\b"#,
                #"\s+"#,
                #"\b[A-Za-z_][A-Za-z0-9_]*\b"#,
            ]
        )

        let classVarDeclaration = Mode(
            scope: [1: "keyword", 3: "keyword"],
            match: [
                #"class\b"#,
                #"\s+"#,
                #"var\b"#,
            ]
        )

        let typeDeclaration = Mode(
            begin: [
                "(struct|protocol|class|extension|enum|actor)",
                #"\s+"#,
                KwsSwift.identifier,
                #"\s*"#,
            ],
            beginScope: [1: "keyword", 3: "title.class"],
            keywords: keywords,
            contains: [
                genericParameters,
            ] + keywordModes + [
                Mode(
                    begin: ":",
                    end: #"\{"#,
                    keywords: keywords,
                    contains: [
                        Mode(
                            scope: "title.class.inherited",
                            match: .re(KwsSwift.typeIdentifier)
                        ),
                    ] + keywordModes,
                    relevance: 0
                ),
            ]
        )

        // Add supported submodes to string interpolation.
        for variant in string.variants ?? [] {
            guard let interpol = variant.contains?.first(where: { $0.label == "interpol" }) else { continue }
            // TODO: Interpolation can contain any expression, so there's room for improvement here.
            interpol.keywords = keywords
            let submodes = keywordModes + builtIns + operators + [
                number,
                string,
            ] + identifiers
            interpol.contains = submodes + [
                Mode(
                    begin: #"\("#,
                    end: #"\)"#,
                    contains: [Mode.selfReference] + submodes
                ),
            ]
        }

        return LanguageDefinition(
            name: "swift",
            root: Mode(
                keywords: keywords,
                contains: comments + [
                    functionOrMacro,
                    initSubscript,
                    classFuncDeclaration,
                    classVarDeclaration,
                    typeDeclaration,
                    operatorDeclaration,
                    precedencegroupDeclaration,
                    Mode(
                        beginKeywords: "import",
                        end: "$",
                        contains: comments,
                        relevance: 0
                    ),
                    regexp,
                ] + keywordModes + builtIns + operators + [
                    number,
                    string,
                ] + identifiers + attributes + [
                    type,
                    tuple,
                ]
            )
        )
    }
}
