import Foundation

extension LanguageCatalog {
    /// Ruby. Port of highlight.js `languages/ruby.js`.
    public static let ruby = LanguageDescriptor(name: "ruby", aliases: ["rb", "gemspec", "podspec", "thor", "irb"]) {
        let rubyMethodRe = #"([a-zA-Z_]\w*[!?=]?|[-+~]@|<<|>>|=~|===?|<=>|[<>]=?|\*\*|[-/+%^&*~`|]|\[\]=?)"#
        let classNameRe = RegexSource.either(
            #"\b([A-Z]+[a-z0-9]+)+"#,
            // ends in caps
            #"\b([A-Z]+[a-z0-9]+)+[A-Z]+"#
        )
        let classNameWithNamespaceRe = RegexSource.concat(classNameRe, #"(::\w+)*"#)
        // very popular ruby built-ins that one might even assume
        // are actual keywords (despite that not being the case)
        let pseudoKws = [
            "include",
            "extend",
            "prepend",
            "public",
            "private",
            "protected",
            "raise",
            "throw",
        ]
        let rubyKeywords = Keywords([
            "variable.constant": Keywords.Group(words: [
                "__FILE__",
                "__LINE__",
                "__ENCODING__",
            ]),
            "variable.language": Keywords.Group(words: [
                "self",
                "super",
            ]),
            "keyword": Keywords.Group(words: [
                "alias",
                "and",
                "begin",
                "BEGIN",
                "break",
                "case",
                "class",
                "defined",
                "do",
                "else",
                "elsif",
                "end",
                "END",
                "ensure",
                "for",
                "if",
                "in",
                "module",
                "next",
                "not",
                "or",
                "redo",
                "require",
                "rescue",
                "retry",
                "return",
                "then",
                "undef",
                "unless",
                "until",
                "when",
                "while",
                "yield",
            ] + pseudoKws),
            "built_in": Keywords.Group(words: [
                "proc",
                "lambda",
                "attr_accessor",
                "attr_reader",
                "attr_writer",
                "define_method",
                "private_constant",
                "module_function",
            ]),
            "literal": Keywords.Group(words: [
                "true",
                "false",
                "nil",
            ]),
        ])
        let yardoctag = Mode(
            scope: "doctag",
            begin: "@[A-Za-z]+"
        )
        let irbObject = Mode(
            begin: "#<",
            end: ">"
        )
        let commentModes: [Mode] = [
            CommonModes.comment("#", "$") { mode in
                mode.contains = [yardoctag]
            },
            CommonModes.comment("^=begin", "^=end") { mode in
                mode.contains = [yardoctag]
                mode.relevance = 10
            },
            CommonModes.comment("^__END__", CommonModes.matchNothingRe),
        ]
        let subst = Mode(
            scope: "subst",
            begin: #"#\{"#,
            end: #"\}"#,
            keywords: rubyKeywords
        )
        let string = Mode(
            scope: "string",
            contains: [
                CommonModes.backslashEscape,
                subst,
            ],
            variants: [
                Mode(begin: "'", end: "'"),
                Mode(begin: "\"", end: "\""),
                Mode(begin: "`", end: "`"),
                Mode(begin: #"%[qQwWx]?\("#, end: #"\)"#),
                Mode(begin: #"%[qQwWx]?\["#, end: #"\]"#),
                Mode(begin: #"%[qQwWx]?\{"#, end: #"\}"#),
                Mode(begin: "%[qQwWx]?<", end: ">"),
                Mode(begin: #"%[qQwWx]?\/"#, end: #"\/"#),
                Mode(begin: "%[qQwWx]?%", end: "%"),
                Mode(begin: "%[qQwWx]?-", end: "-"),
                Mode(begin: #"%[qQwWx]?\|"#, end: #"\|"#),
                // in the following expressions, \B in the beginning suppresses recognition of ?-sequences
                // where ? is the last character of a preceding identifier, as in: `func?4`
                Mode(begin: #"\B\?(\\\d{1,3})"#),
                Mode(begin: #"\B\?(\\x[A-Fa-f0-9]{1,2})"#),
                Mode(begin: #"\B\?(\\u\{?[A-Fa-f0-9]{1,6}\}?)"#),
                Mode(begin: #"\B\?(\\M-\\C-|\\M-\\c|\\c\\M-|\\M-|\\C-\\M-)[\x20-\x7e]"#),
                Mode(begin: #"\B\?\\(c|C-)[\x20-\x7e]"#),
                Mode(begin: #"\B\?\\?\S"#),
                // heredocs
                Mode(
                    // this guard makes sure that we have an entire heredoc and not a false
                    // positive (auto-detect, etc.)
                    begin: .re(RegexSource.concat(
                        #"<<[-~]?'?"#,
                        RegexSource.lookahead(#"(\w+)(?=\W)[^\n]*\n(?:[^\n]*\n)*?\s*\1\b"#)
                    )),
                    contains: [
                        Mode(
                            begin: #"(\w+)"#,
                            end: #"(\w+)"#,
                            endSameAsBegin: true,
                            contains: [
                                CommonModes.backslashEscape,
                                subst,
                            ]
                        ),
                    ]
                ),
            ]
        )

        // Ruby syntax is underdocumented, but this grammar seems to be accurate
        // as of version 2.7.2 (confirmed with (irb and `Ripper.sexp(...)`)
        // https://docs.ruby-lang.org/en/2.7.0/doc/syntax/literals_rdoc.html#label-Numbers
        let decimal = "[1-9](_?[0-9])*|0"
        let digits = "[0-9](_?[0-9])*"
        let number = Mode(
            scope: "number",
            variants: [
                // decimal integer/float, optionally exponential or rational, optionally imaginary
                Mode(begin: .re("\\b(\(decimal))(\\.(\(digits)))?([eE][+-]?(\(digits))|r)?i?\\b")),

                // explicit decimal/binary/octal/hexadecimal integer,
                // optionally rational and/or imaginary
                Mode(begin: "\\b0[dD][0-9](_?[0-9])*r?i?\\b"),
                Mode(begin: "\\b0[bB][0-1](_?[0-1])*r?i?\\b"),
                Mode(begin: "\\b0[oO][0-7](_?[0-7])*r?i?\\b"),
                Mode(begin: "\\b0[xX][0-9a-fA-F](_?[0-9a-fA-F])*r?i?\\b"),

                // 0-prefixed implicit octal integer, optionally rational and/or imaginary
                Mode(begin: "\\b0(_?[0-7])+r?i?\\b"),
            ],
            relevance: 0
        )

        let params = Mode(
            variants: [
                Mode(match: #"\(\)"#),
                Mode(
                    scope: "params",
                    begin: #"\("#,
                    end: #"(?=\))"#,
                    keywords: rubyKeywords,
                    excludeBegin: true,
                    endsParent: true
                ),
            ]
        )

        let includeExtend = Mode(
            scope: [2: "title.class"],
            match: [
                #"(include|extend)\s+"#,
                classNameWithNamespaceRe,
            ],
            keywords: rubyKeywords
        )

        let classDefinition = Mode(
            scope: [
                2: "title.class",
                4: "title.class.inherited",
            ],
            keywords: rubyKeywords,
            variants: [
                Mode(
                    match: [
                        #"class\s+"#,
                        classNameWithNamespaceRe,
                        #"\s+<\s+"#,
                        classNameWithNamespaceRe,
                    ]
                ),
                Mode(
                    match: [
                        #"\b(class|module)\s+"#,
                        classNameWithNamespaceRe,
                    ]
                ),
            ]
        )

        let upperCaseConstant = Mode(
            scope: "variable.constant",
            match: #"\b[A-Z][A-Z_0-9]+\b"#,
            relevance: 0
        )

        let methodDefinition = Mode(
            scope: [
                1: "keyword",
                3: "title.function",
            ],
            match: [
                "def", #"\s+"#,
                rubyMethodRe,
            ],
            contains: [
                params,
            ]
        )

        let objectCreation = Mode(
            scope: [1: "title.class"],
            match: [
                classNameWithNamespaceRe,
                #"\.new[. (]"#,
            ],
            relevance: 0
        )

        // CamelCase
        let classReference = Mode(
            scope: "title.class",
            match: .re(classNameRe),
            relevance: 0
        )

        let rubyDefaultContains: [Mode] = [
            string,
            classDefinition,
            includeExtend,
            objectCreation,
            upperCaseConstant,
            classReference,
            methodDefinition,
            // swallow namespace qualifiers before symbols
            Mode(begin: .re(CommonModes.identRe + "::")),
            Mode(
                scope: "symbol",
                begin: .re(CommonModes.underscoreIdentRe + "(!|\\?)?:"),
                relevance: 0
            ),
            Mode(
                scope: "symbol",
                begin: #":(?!\s)"#,
                contains: [
                    string,
                    Mode(begin: .re(rubyMethodRe)),
                ],
                relevance: 0
            ),
            number,
            Mode(
                // negative-look forward attempts to prevent false matches like:
                // @ident@ or $ident$ that might indicate this is not ruby at all
                scope: "variable",
                begin: #"(\$\W)|((\$|@@?)(\w+))(?=[^@$?])(?![A-Za-z])(?![@$?'])"#
            ),
            Mode(
                scope: "params",
                begin: #"\|(?!=)"#,
                end: #"\|"#,
                keywords: rubyKeywords,
                relevance: 0, // this could be a lot of things (in other languages) other than params
                excludeBegin: true,
                excludeEnd: true
            ),
            // regexp container
            Mode(
                begin: .re("(" + CommonModes.reStartersRe + "|unless)\\s*"),
                keywords: "unless",
                contains: [
                    Mode(
                        scope: "regexp",
                        illegal: [#"\n"#],
                        contains: [
                            CommonModes.backslashEscape,
                            subst,
                        ],
                        variants: [
                            Mode(begin: "/", end: "/[a-z]*"),
                            Mode(begin: #"%r\{"#, end: #"\}[a-z]*"#),
                            Mode(begin: "%r\\(", end: "\\)[a-z]*"),
                            Mode(begin: "%r!", end: "![a-z]*"),
                            Mode(begin: "%r\\[", end: "\\][a-z]*"),
                        ]
                    ),
                    irbObject,
                ] + commentModes,
                relevance: 0
            ),
        ] + [irbObject] + commentModes

        subst.contains = rubyDefaultContains
        params.contains = rubyDefaultContains

        // >>
        // ?>
        let simplePrompt = "[>?]>"
        // irb(main):001:0>
        let defaultPrompt = "[\\w#]+\\(\\w+\\):\\d+:\\d+[>*]"
        let rvmPrompt = "(\\w+-)?\\d+\\.\\d+\\.\\d+(p\\d+)?[^\\d][^>]+>"

        let irbDefault: [Mode] = [
            Mode(
                begin: #"^\s*=>"#,
                starts: Mode(
                    end: "$",
                    contains: rubyDefaultContains
                )
            ),
            Mode(
                scope: "meta.prompt",
                begin: .re("^(" + simplePrompt + "|" + defaultPrompt + "|" + rvmPrompt + ")(?=[ ])"),
                starts: Mode(
                    end: "$",
                    keywords: rubyKeywords,
                    contains: rubyDefaultContains
                )
            ),
        ]

        return LanguageDefinition(
            name: "ruby",
            aliases: ["rb", "gemspec", "podspec", "thor", "irb"],
            root: Mode(
                keywords: rubyKeywords,
                illegal: [#"\/\*"#],
                contains: [CommonModes.shebang(binary: "ruby")]
                    + irbDefault
                    + ([irbObject] + commentModes)
                    + rubyDefaultContains
            )
        )
    }
}
