import Foundation

extension LanguageCatalog {
    /// Erlang. Port of highlight.js `languages/erlang.js`.
    public static let erlang = LanguageDescriptor(name: "erlang", aliases: ["erl"]) {
        let basicAtomRe = "[a-z'][a-zA-Z0-9_']*"
        let functionNameRe = "(" + basicAtomRe + ":" + basicAtomRe + "|" + basicAtomRe + ")"
        let erlangReserved = Keywords([
            "keyword":
                "after and andalso|10 band begin bnot bor bsl bzr bxor case catch cond div end fun if let not of orelse|10 query receive rem try when xor maybe else",
            "literal": "false true",
        ])

        let comment = CommonModes.comment("%", "$")
        let number = Mode(
            scope: "number",
            begin: #"\b(\d+(_\d+)*#[a-fA-F0-9]+(_[a-fA-F0-9]+)*|\d+(_\d+)*(\.\d+(_\d+)*)?([eE][-+]?\d+)?)"#,
            relevance: 0
        )
        let namedFun = Mode(begin: .re(#"fun\s+"# + basicAtomRe + #"/\d+"#))
        let functionCallParen = Mode(
            begin: #"\("#,
            end: #"\)"#,
            relevance: 0,
            returnEnd: true,
            endsWithParent: true
            // "contains" defined later
        )
        let functionCall = Mode(
            begin: .re(functionNameRe + #"\("#),
            end: #"\)"#,
            contains: [
                Mode(begin: .re(functionNameRe), relevance: 0),
                functionCallParen,
            ],
            relevance: 0,
            returnBegin: true
        )
        let tuple = Mode(
            begin: #"\{"#,
            end: #"\}"#,
            relevance: 0
            // "contains" defined later
        )
        let var1 = Mode(
            begin: #"\b_([A-Z][A-Za-z0-9_]*)?"#,
            relevance: 0
        )
        let var2 = Mode(
            begin: "[A-Z][a-zA-Z0-9_]*",
            relevance: 0
        )
        let recordAccessBrace = Mode(
            begin: #"\{"#,
            end: #"\}"#,
            relevance: 0
            // "contains" defined later
        )
        let recordAccess = Mode(
            begin: .re("#" + CommonModes.underscoreIdentRe),
            contains: [
                Mode(begin: .re("#" + CommonModes.underscoreIdentRe), relevance: 0),
                recordAccessBrace,
            ],
            relevance: 0,
            returnBegin: true
        )
        let charLiteral = Mode(
            scope: "string",
            match: #"\$(\\([^0-9]|[0-9]{1,3}|)|.)"#
        )
        let tripleQuote = Mode(
            scope: "string",
            match: #""""("*)(?!")[\s\S]*?"""\1"#
        )

        let sigil = Mode(
            scope: "string",
            contains: [CommonModes.backslashEscape],
            variants: [
                Mode(match: #"~\w?"""("*)(?!")[\s\S]*?"""\1"#),
                Mode(begin: #"~\w?\("#, end: #"\)"#),
                Mode(begin: #"~\w?\["#, end: #"\]"#),
                Mode(begin: #"~\w?\{"#, end: #"\}"#),
                Mode(begin: #"~\w?<"#, end: ">"),
                Mode(begin: #"~\w?\/"#, end: #"\/"#),
                Mode(begin: #"~\w?\|"#, end: #"\|"#),
                Mode(begin: "~\\w?'", end: "'"),
                Mode(begin: "~\\w?\"", end: "\""),
                Mode(begin: "~\\w?`", end: "`"),
                Mode(begin: "~\\w?#", end: "#"),
            ]
        )

        let blockStatements = Mode(
            beginKeywords: "fun receive if try case maybe",
            end: "end",
            keywords: erlangReserved
        )
        blockStatements.contains = [
            comment,
            namedFun,
            { let m = CommonModes.aposStringMode; m.scope = ScopeRef.none; return m }(),
            blockStatements,
            functionCall,
            sigil,
            tripleQuote,
            CommonModes.quoteStringMode,
            number,
            tuple,
            var1,
            var2,
            recordAccess,
            charLiteral,
        ]

        let basicModes = [
            comment,
            namedFun,
            blockStatements,
            functionCall,
            sigil,
            tripleQuote,
            CommonModes.quoteStringMode,
            number,
            tuple,
            var1,
            var2,
            recordAccess,
            charLiteral,
        ]
        functionCallParen.contains = basicModes
        tuple.contains = basicModes
        recordAccessBrace.contains = basicModes

        let directives = [
            "-module",
            "-record",
            "-undef",
            "-export",
            "-ifdef",
            "-ifndef",
            "-author",
            "-copyright",
            "-doc",
            "-moduledoc",
            "-vsn",
            "-import",
            "-include",
            "-include_lib",
            "-compile",
            "-define",
            "-else",
            "-endif",
            "-file",
            "-behaviour",
            "-behavior",
            "-spec",
            "-on_load",
            "-nifs",
        ]

        let params = Mode(
            scope: "params",
            begin: #"\("#,
            end: #"\)"#,
            contains: basicModes
        )

        return LanguageDefinition(
            name: "erlang",
            aliases: ["erl"],
            root: Mode(
                keywords: erlangReserved,
                illegal: [#"(</|\*=|\+=|-=|/\*|\*/|\(\*|\*\))"#],
                contains: [
                    Mode(
                        scope: "function",
                        begin: .re("^" + basicAtomRe + #"\s*\("#),
                        end: "->",
                        illegal: [#"\(|#|//|/\*|\\|:|;"#],
                        contains: [
                            params,
                            { let m = CommonModes.titleMode; m.begin = .re(basicAtomRe); return m }(),
                        ],
                        starts: Mode(
                            end: #";|\."#,
                            keywords: erlangReserved,
                            contains: basicModes
                        ),
                        returnBegin: true
                    ),
                    comment,
                    Mode(
                        begin: "^-",
                        end: #"\."#,
                        keywords: Keywords(
                            pattern: "-" + CommonModes.identRe,
                            keyword: Keywords.Group(words: directives.map { "\($0)|1.5" })
                        ),
                        contains: [
                            params,
                            sigil,
                            tripleQuote,
                            CommonModes.quoteStringMode,
                        ],
                        relevance: 0,
                        excludeEnd: true,
                        returnBegin: true
                    ),
                    number,
                    sigil,
                    tripleQuote,
                    CommonModes.quoteStringMode,
                    recordAccess,
                    var1,
                    var2,
                    tuple,
                    charLiteral,
                    Mode(begin: #"\.$"#), // relevance booster
                ]
            )
        )
    }
}
