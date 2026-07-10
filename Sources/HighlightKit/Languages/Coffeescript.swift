import Foundation

extension LanguageCatalog {
    /// CoffeeScript. Port of highlight.js `languages/coffeescript.js`.
    public static let coffeescript = LanguageDescriptor(name: "coffeescript", aliases: ["coffee", "cson", "iced"]) {
        let coffeeBuiltIns = [
            "npm",
            "print",
        ]
        let coffeeLiterals = [
            "yes",
            "no",
            "on",
            "off",
        ]
        let coffeeKeywords = [
            "then",
            "unless",
            "until",
            "loop",
            "by",
            "when",
            "and",
            "or",
            "is",
            "isnt",
            "not",
        ]
        let notValidKeywords = [
            "var",
            "const",
            "let",
            "function",
            "static",
        ]
        let keywords = Keywords([
            "keyword": Keywords.Group(words: (Ecmascript.keywords + coffeeKeywords).filter { !notValidKeywords.contains($0) }),
            "literal": Keywords.Group(words: Ecmascript.literals + coffeeLiterals),
            "built_in": Keywords.Group(words: Ecmascript.builtIns + coffeeBuiltIns),
        ])
        let jsIdentRe = "[A-Za-z$_][0-9A-Za-z$_]*"
        let subst = Mode(
            scope: "subst",
            begin: #"#\{"#,
            end: #"\}"#,
            keywords: keywords
        )
        let expressions: [Mode] = [
            CommonModes.binaryNumberMode,
            {
                // a number tries to eat the following slash to prevent
                // treating it as a regexp
                let m = CommonModes.cNumberMode
                m.starts = Mode(end: #"(\s*/)?"#, relevance: 0)
                return m
            }(),
            Mode(
                scope: "string",
                variants: [
                    Mode(begin: "'''", end: "'''", contains: [CommonModes.backslashEscape]),
                    Mode(begin: "'", end: "'", contains: [CommonModes.backslashEscape]),
                    Mode(begin: "\"\"\"", end: "\"\"\"", contains: [CommonModes.backslashEscape, subst]),
                    Mode(begin: "\"", end: "\"", contains: [CommonModes.backslashEscape, subst]),
                ]
            ),
            Mode(
                scope: "regexp",
                variants: [
                    Mode(begin: "///", end: "///", contains: [subst, CommonModes.hashCommentMode]),
                    Mode(begin: #"//[gim]{0,3}(?=\W)"#, relevance: 0),
                    // regex can't start with space to parse x / 2 / 3 as two divisions
                    // regex can't start with *, and it supports an "illegal" in the main mode
                    Mode(begin: #"\/(?![ *]).*?(?![\\]).\/[gim]{0,3}(?=\W)"#),
                ]
            ),
            Mode(begin: .re("@" + jsIdentRe)), // relevance booster
            Mode(
                variants: [
                    Mode(begin: "```", end: "```"),
                    Mode(begin: "`", end: "`"),
                ],
                subLanguage: ["javascript"],
                excludeBegin: true,
                excludeEnd: true
            ),
        ]
        subst.contains = expressions

        let title: Mode = {
            let m = CommonModes.titleMode
            m.begin = .re(jsIdentRe)
            return m
        }()
        let possibleParamsRe = #"(\(.*\)\s*)?\B[-=]>"#
        // We need another contained nameless mode to not have every nested
        // pair of parens to be called "params"
        let params = Mode(
            scope: "params",
            begin: #"\([^\(]"#,
            contains: [
                Mode(
                    begin: #"\("#,
                    end: #"\)"#,
                    keywords: keywords,
                    contains: [Mode.selfReference] + expressions
                ),
            ],
            returnBegin: true
        )

        let classDefinition = Mode(
            scope: [2: "title.class", 4: "title.class.inherited"],
            keywords: keywords,
            variants: [
                Mode(match: [#"class\s+"#, jsIdentRe, #"\s+extends\s+"#, jsIdentRe]),
                Mode(match: [#"class\s+"#, jsIdentRe]),
            ]
        )

        return LanguageDefinition(
            name: "coffeescript",
            aliases: ["coffee", "cson", "iced"],
            root: Mode(
                keywords: keywords,
                illegal: [#"/\*"#],
                contains: expressions + [
                    CommonModes.comment("###", "###"),
                    CommonModes.hashCommentMode,
                    Mode(
                        scope: "function",
                        begin: .re("^\\s*" + jsIdentRe + "\\s*=\\s*" + possibleParamsRe),
                        end: "[-=]>",
                        contains: [title, params],
                        returnBegin: true
                    ),
                    Mode(
                        // anonymous function start
                        begin: #"[:\(,=]\s*"#,
                        contains: [
                            Mode(
                                scope: "function",
                                begin: .re(possibleParamsRe),
                                end: "[-=]>",
                                contains: [params],
                                returnBegin: true
                            ),
                        ],
                        relevance: 0
                    ),
                    classDefinition,
                    Mode(
                        begin: .re(jsIdentRe + ":"),
                        end: ":",
                        relevance: 0,
                        returnBegin: true,
                        returnEnd: true
                    ),
                ]
            )
        )
    }
}
