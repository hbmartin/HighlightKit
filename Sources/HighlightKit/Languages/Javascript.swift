import Foundation

/// JavaScript grammar builder — shared with TypeScript, which extends the
/// mode tree this produces. Port of highlight.js `languages/javascript.js`.
enum JavascriptGrammar {
    /// Mutable references TypeScript needs when extending JavaScript.
    struct Exports {
        let definition: LanguageDefinition
        let paramsContains: [Mode]
        let classReference: Mode
    }

    static func make() -> Exports {
        let identRe = Ecmascript.identRe

        // "<Booger" — is there a matching "</Booger" later on?
        @Sendable func hasClosingTag(_ match: CallbackMatch, after: Int) -> Bool {
            guard let opening = match[0] else { return false }
            let tag = "</" + opening.dropFirst()
            let input = match.input
            let searchRange = NSRange(location: after, length: input.length - after)
            return input.range(of: tag, options: [.literal], range: searchRange).location != NSNotFound
        }

        let equalsAhead = try! NSRegularExpression(pattern: #"\s*="#)
        let extendsAhead = try! NSRegularExpression(pattern: #"\s+extends\s+"#)

        // Carefully checks an opening `<Tag` to see whether it truly is a
        // JSX tag and not a comparison/generic-type false positive.
        let isTrulyOpeningTag: ModeCallback = { match, response in
            guard let matched = match[0] else { return }
            let afterMatchIndex = match.index + (matched as NSString).length
            let input = match.input

            let nextChar: UInt16? = afterMatchIndex < input.length ? input.character(at: afterMatchIndex) : nil
            if let nextChar, nextChar == UInt16(UInt8(ascii: "<")) || nextChar == UInt16(UInt8(ascii: ",")) {
                // `<Array<Array<number>>` nested type, or `<T, A>` generics
                response.ignoreMatch()
                return
            }

            if let nextChar, nextChar == UInt16(UInt8(ascii: ">")) {
                // `<something>` — without a matching closing tag, ignore
                if !hasClosingTag(match, after: afterMatchIndex) {
                    response.ignoreMatch()
                }
            }

            let rest = NSRange(location: afterMatchIndex, length: input.length - afterMatchIndex)
            // `<T = any>(key?: string) => Modify<` — template typing
            if equalsAhead.firstMatch(in: input as String, options: [.anchored], range: rest) != nil {
                response.ignoreMatch()
                return
            }
            // `<From extends string>` smells like a type, not HTML
            if extendsAhead.firstMatch(in: input as String, options: [.anchored], range: rest) != nil {
                response.ignoreMatch()
                return
            }
        }

        let keywords = Keywords(
            pattern: identRe,
            [
                "keyword": Keywords.Group(words: Ecmascript.keywords),
                "literal": Keywords.Group(words: Ecmascript.literals),
                "built_in": Keywords.Group(words: Ecmascript.builtIns),
                "variable.language": Keywords.Group(words: Ecmascript.builtInVariables),
            ]
        )

        // https://tc39.es/ecma262/#sec-literals-numeric-literals
        let decimalDigits = "[0-9](_?[0-9])*"
        let frac = "\\.(\(decimalDigits))"
        // DecimalIntegerLiteral, including Annex B NonOctalDecimalIntegerLiteral
        let decimalInteger = "0|[1-9](_?[0-9])*|0[0-7]*[89][0-9]*"
        let number = Mode(
            scope: "number",
            variants: [
                // DecimalLiteral
                Mode(begin: .re("(\\b(\(decimalInteger))((\(frac))|\\.)?|(\(frac)))[eE][+-]?(\(decimalDigits))\\b")),
                Mode(begin: .re("\\b(\(decimalInteger))\\b((\(frac))\\b|\\.)?|(\(frac))\\b")),
                // DecimalBigIntegerLiteral
                Mode(begin: .re("\\b(0|[1-9](_?[0-9])*)n\\b")),
                // NonDecimalIntegerLiteral
                Mode(begin: "\\b0[xX][0-9a-fA-F](_?[0-9a-fA-F])*n?\\b"),
                Mode(begin: "\\b0[bB][0-1](_?[0-1])*n?\\b"),
                Mode(begin: "\\b0[oO][0-7](_?[0-7])*n?\\b"),
                // LegacyOctalIntegerLiteral (no underscore separators)
                Mode(begin: "\\b0[0-7]+n?\\b"),
            ],
            relevance: 0
        )

        let subst = Mode(
            scope: "subst",
            begin: #"\$\{"#,
            end: #"\}"#,
            keywords: keywords
            // contains is defined later (cyclic)
        )
        // Note: in the upstream JavaScript source these begins are written
        // as '\.?html`' etc., where `\.` inside a *string literal* is just
        // `.` — so the actual regex is `.?html\``.
        let htmlTemplate = Mode(
            begin: ".?html`",
            end: "",
            starts: Mode(
                end: "`",
                contains: [CommonModes.backslashEscape, subst],
                subLanguage: ["xml"]
            )
        )
        let cssTemplate = Mode(
            begin: ".?css`",
            end: "",
            starts: Mode(
                end: "`",
                contains: [CommonModes.backslashEscape, subst],
                subLanguage: ["css"]
            )
        )
        let graphqlTemplate = Mode(
            begin: ".?gql`",
            end: "",
            starts: Mode(
                end: "`",
                contains: [CommonModes.backslashEscape, subst],
                subLanguage: ["graphql"]
            )
        )
        let templateString = Mode(
            scope: "string",
            begin: "`",
            end: "`",
            contains: [CommonModes.backslashEscape, subst]
        )
        let jsdocComment = CommonModes.comment(#"/\*\*(?!/)"#, #"\*/"#) { mode in
            mode.relevance = 0
            mode.contains = [
                Mode(
                    begin: "(?=@[A-Za-z]+)",
                    contains: [
                        Mode(scope: "doctag", begin: "@[A-Za-z]+"),
                        Mode(
                            scope: "type",
                            begin: #"\{"#,
                            end: #"\}"#,
                            relevance: 0,
                            excludeBegin: true,
                            excludeEnd: true
                        ),
                        Mode(
                            scope: "variable",
                            begin: .re(identRe + #"(?=\s*(-)|$)"#),
                            relevance: 0,
                            endsParent: true
                        ),
                        // eat spaces (not newlines) so we can find
                        // types or variables
                        Mode(begin: #"(?=[^\n])\s"#, relevance: 0),
                    ],
                    relevance: 0
                ),
            ]
        }
        let comment = Mode(
            scope: "comment",
            variants: [
                jsdocComment,
                CommonModes.cBlockCommentMode,
                CommonModes.cLineCommentMode,
            ]
        )
        let substInternals: [Mode] = [
            CommonModes.aposStringMode,
            CommonModes.quoteStringMode,
            htmlTemplate,
            cssTemplate,
            graphqlTemplate,
            templateString,
            // Skip numbers when they are part of a variable name
            Mode(match: #"\$\d+"#),
            number,
            // NOT the regexp mode here — see hljs issue #3288
        ]
        subst.contains = substInternals + [
            // we need to pair up {} inside our subst to prevent it from
            // ending too early by matching another }
            Mode(
                begin: #"\{"#,
                end: #"\}"#,
                keywords: keywords,
                contains: [Mode.selfReference] + substInternals
            ),
        ]
        let substAndComments = [comment] + subst.contains!
        let paramsContains = substAndComments + [
            // eat recursive parens in sub expressions
            Mode(
                begin: #"(\s*)\("#,
                end: #"\)"#,
                keywords: keywords,
                contains: [Mode.selfReference] + substAndComments
            ),
        ]
        let params = Mode(
            scope: "params",
            begin: #"(\s*)\("#, // to match the params with
            end: #"\)"#,
            keywords: keywords,
            contains: paramsContains,
            excludeBegin: true,
            excludeEnd: true
        )

        // ES6 classes
        let classOrExtends = Mode(
            variants: [
                // class Car extends vehicle
                Mode(
                    scope: [1: "keyword", 3: "title.class", 5: "keyword", 7: "title.class.inherited"],
                    match: ["class", #"\s+"#, identRe, #"\s+"#, "extends", #"\s+"#,
                            identRe + "(" + #"\."# + identRe + ")*"]
                ),
                // class Car
                Mode(
                    scope: [1: "keyword", 3: "title.class"],
                    match: ["class", #"\s+"#, identRe]
                ),
            ]
        )

        let classReference = Mode(
            scope: "title.class",
            match: .re(RegexSource.either(
                #"\bJSON"#,
                // Float32Array, OutT
                #"\b[A-Z][a-z]+([A-Z][a-z]*|\d)*"#,
                // CSSFactory, CSSFactoryT
                #"\b[A-Z]{2,}([A-Z][a-z]+|\d)+([A-Z][a-z]*)*"#,
                // FPs, FPsT
                #"\b[A-Z]{2,}[a-z]+([A-Z][a-z]+|\d)*([A-Z][a-z]*)*"#
            )),
            keywords: Keywords([
                // so we still get relevance credit for JS library classes
                "_": Keywords.Group(words: Ecmascript.types + Ecmascript.errorTypes),
            ]),
            relevance: 0
        )

        let useStrict = Mode(
            scope: "meta",
            begin: #"^\s*['"]use (strict|asm)['"]"#,
            relevance: 10,
            label: "use_strict"
        )

        let functionDefinition = Mode(
            scope: [1: "keyword", 3: "title.function"],
            illegal: ["%"],
            contains: [params],
            variants: [
                Mode(match: ["function", #"\s+"#, identRe, #"(?=\s*\()"#]),
                // anonymous function
                Mode(match: ["function", #"\s*(?=\()"#]),
            ],
            label: "func.def"
        )

        let upperCaseConstant = Mode(
            scope: "variable.constant",
            match: #"\b[A-Z][A-Z_0-9]+\b"#,
            relevance: 0
        )

        let functionCall = Mode(
            scope: "title.function",
            match: .re(Ecmascript.functionCallPattern),
            relevance: 0
        )

        let propertyAccess = Mode(
            scope: "property",
            begin: .re(#"\."# + RegexSource.lookahead(identRe + #"(?![0-9A-Za-z$_(])"#)),
            end: .re(identRe),
            keywords: "prototype",
            relevance: 0,
            excludeBegin: true
        )

        let getterOrSetter = Mode(
            scope: [1: "keyword", 3: "title.function"],
            match: ["get|set", #"\s+"#, identRe, #"(?=\()"#],
            contains: [
                Mode(begin: #"\(\)"#), // eat to avoid empty params
                params,
            ]
        )

        let funcLeadInRe = "(\\("
            + "[^()]*(\\("
            + "[^()]*(\\("
            + "[^()]*"
            + "\\)[^()]*)*"
            + "\\)[^()]*)*"
            + "\\)|" + CommonModes.underscoreIdentRe + ")\\s*=>"

        let functionVariable = Mode(
            scope: [1: "keyword", 3: "title.function"],
            match: [
                "const|var|let", #"\s+"#,
                identRe, #"\s*"#,
                #"=\s*"#,
                #"(async\s*)?"#, // async is optional
                RegexSource.lookahead(funcLeadInRe),
            ],
            keywords: "async",
            contains: [params]
        )

        let shebang = CommonModes.shebang(binary: "node", relevance: 5)
        shebang.label = "shebang"

        // JSX
        let fragmentBegin = "<>"
        let fragmentEnd = "</>"
        let xmlSelfClosing = #"<[A-Za-z0-9\\._:-]+\s*/>"#
        let xmlTagBegin = #"<[A-Za-z0-9\\._:-]+"#
        let xmlTagEnd = #"/[A-Za-z0-9\\._:-]+>|/>"#

        let definition = LanguageDefinition(
            name: "javascript",
            aliases: ["js", "jsx", "mjs", "cjs"],
            root: Mode(
                keywords: keywords,
                illegal: ["#(?![$_A-Za-z])"],
                contains: [
                    shebang,
                    useStrict,
                    CommonModes.aposStringMode,
                    CommonModes.quoteStringMode,
                    htmlTemplate,
                    cssTemplate,
                    graphqlTemplate,
                    templateString,
                    comment,
                    // Skip numbers when they are part of a variable name
                    Mode(match: #"\$\d+"#),
                    number,
                    classReference,
                    Mode(
                        scope: "attr",
                        match: .re(identRe + RegexSource.lookahead(":")),
                        relevance: 0
                    ),
                    functionVariable,
                    // "value" container
                    Mode(
                        begin: .re(Ecmascript.valueContainerLeadIn),
                        keywords: "return throw case",
                        contains: [
                            comment,
                            CommonModes.regexpMode,
                            Mode(
                                scope: "function",
                                // we have to count parens to find the correct
                                // bounding ( ) before the =>; there could be
                                // any number of sub-expressions inside
                                begin: .re(funcLeadInRe),
                                end: #"\s*=>"#,
                                contains: [
                                    Mode(
                                        scope: "params",
                                        variants: [
                                            Mode(begin: .re(CommonModes.underscoreIdentRe), relevance: 0),
                                            Mode(scope: ScopeRef.none, begin: #"\(\s*\)"#, skip: true),
                                            Mode(
                                                begin: #"(\s*)\("#,
                                                end: #"\)"#,
                                                keywords: keywords,
                                                contains: paramsContains,
                                                excludeBegin: true,
                                                excludeEnd: true
                                            ),
                                        ]
                                    ),
                                ],
                                returnBegin: true
                            ),
                            // could be a comma delimited list of params to a function call
                            Mode(begin: ",", relevance: 0),
                            Mode(match: #"\s+"#, relevance: 0),
                            // JSX
                            Mode(
                                contains: [
                                    Mode(
                                        begin: .re(xmlTagBegin),
                                        end: .re(xmlTagEnd),
                                        contains: [Mode.selfReference],
                                        skip: true
                                    ),
                                ],
                                variants: [
                                    Mode(begin: .re(fragmentBegin), end: .re(fragmentEnd)),
                                    Mode(match: .re(xmlSelfClosing)),
                                    Mode(
                                        begin: .re(xmlTagBegin),
                                        end: .re(xmlTagEnd),
                                        // carefully check the opening tag to see if it
                                        // truly is a tag and not a false positive
                                        onBegin: isTrulyOpeningTag
                                    ),
                                ],
                                subLanguage: ["xml"]
                            ),
                        ],
                        relevance: 0
                    ),
                    functionDefinition,
                    // prevent this from getting swallowed up by function
                    // since they appear "function like"
                    Mode(beginKeywords: "while if switch catch for"),
                    // we have to count the parens to make sure we actually
                    // have the correct bounding ( ) for the function def
                    Mode(
                        begin: .re(
                            "\\b(?!function)" + CommonModes.underscoreIdentRe
                            + "\\("
                            + "[^()]*(\\("
                            + "[^()]*(\\("
                            + "[^()]*"
                            + "\\)[^()]*)*"
                            + "\\)[^()]*)*"
                            + "\\)\\s*\\{"
                        ),
                        contains: [
                            params,
                            Mode(scope: "title.function", begin: .re(identRe), relevance: 0),
                        ],
                        label: "func.def",
                        returnBegin: true
                    ),
                    // catch ... so it won't trigger the property rule below
                    Mode(match: #"\.\.\."#, relevance: 0),
                    propertyAccess,
                    // hack: prevents detection of keywords in some
                    // circumstances: .keyword() / $keyword = x
                    Mode(match: .re("\\$" + identRe), relevance: 0),
                    Mode(
                        scope: [1: "title.function"],
                        match: [#"\bconstructor(?=\s*\()"#],
                        contains: [params]
                    ),
                    functionCall,
                    upperCaseConstant,
                    classOrExtends,
                    getterOrSetter,
                    // relevance booster for a pattern common to JS libs:
                    // `$(something)` and `$.something`
                    Mode(match: #"\$[(.]"#),
                ]
            )
        )
        return Exports(
            definition: definition,
            paramsContains: paramsContains,
            classReference: classReference
        )
    }
}

extension LanguageCatalog {
    /// JavaScript (with JSX). Port of highlight.js `languages/javascript.js`.
    public static let javascript = LanguageDescriptor(
        name: "javascript",
        aliases: ["js", "jsx", "mjs", "cjs"]
    ) {
        JavascriptGrammar.make().definition
    }
}
