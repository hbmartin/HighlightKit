import Foundation

extension LanguageCatalog {
    /// R. Port of highlight.js `languages/r.js`.
    public static let r = LanguageDescriptor(name: "r") {
        // Identifiers in R cannot start with `_`, but they can start with
        // `.` if it is not immediately followed by a digit. Quoted
        // identifiers (`…`) are handled in a separate mode.
        let identRe = #"(?:(?:[a-zA-Z]|\.[._a-zA-Z])[._a-zA-Z0-9]*)|\.(?!\d)"#
        let numberTypesRe = RegexSource.either(
            // Special case: only hexadecimal binary powers can contain fractions
            #"0[xX][0-9a-fA-F]+\.[0-9a-fA-F]*[pP][+-]?\d+i?"#,
            // Hexadecimal numbers without fraction and optional binary power
            #"0[xX][0-9a-fA-F]+(?:[pP][+-]?\d+)?[Li]?"#,
            // Decimal numbers
            #"(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?[Li]?"#
        )
        let operatorsRe = #"[=!<>:]=|\|\||&&|:::?|<-|<<-|->>|->|\|>|[-+*\/?!$&|:<=>@^~]|\*\*"#
        let punctuationRe = RegexSource.either(
            #"[()]"#,
            #"[{}]"#,
            #"\[\["#,
            #"[\[\]]"#,
            #"\\"#,
            #","#
        )

        return LanguageDefinition(
            name: "r",
            root: Mode(
                keywords: Keywords(
                    pattern: identRe,
                    [
                        "keyword":
                            "function if in break next repeat else for while",
                        "literal": Keywords.Group(stringLiteral:
                            "NULL NA TRUE FALSE Inf NaN NA_integer_|10 NA_real_|10 "
                            + "NA_character_|10 NA_complex_|10"
                        ),
                        "built_in": Keywords.Group(stringLiteral:
                            // Builtin constants
                            "LETTERS letters month.abb month.name pi T F "
                            // Primitive functions
                            + "abs acos acosh all any anyNA Arg as.call as.character "
                            + "as.complex as.double as.environment as.integer as.logical "
                            + "as.null.default as.numeric as.raw asin asinh atan atanh attr "
                            + "attributes baseenv browser c call ceiling class Conj cos cosh "
                            + "cospi cummax cummin cumprod cumsum digamma dim dimnames "
                            + "emptyenv exp expression floor forceAndCall gamma gc.time "
                            + "globalenv Im interactive invisible is.array is.atomic is.call "
                            + "is.character is.complex is.double is.environment is.expression "
                            + "is.finite is.function is.infinite is.integer is.language "
                            + "is.list is.logical is.matrix is.na is.name is.nan is.null "
                            + "is.numeric is.object is.pairlist is.raw is.recursive is.single "
                            + "is.symbol lazyLoadDBfetch length lgamma list log max min "
                            + "missing Mod names nargs nzchar oldClass on.exit pos.to.env "
                            + "proc.time prod quote range Re rep retracemem return round "
                            + "seq_along seq_len seq.int sign signif sin sinh sinpi sqrt "
                            + "standardGeneric substitute sum switch tan tanh tanpi tracemem "
                            + "trigamma trunc unclass untracemem UseMethod xtfrm"
                        ),
                    ]
                ),
                contains: [
                    // Roxygen comments
                    CommonModes.comment("#'", "$") { mode in
                        mode.contains = [
                            Mode(
                                // Handle `@examples` separately to cause all
                                // subsequent code until the next `@`-tag on its
                                // own line to be kept as-is, preventing
                                // highlighting.
                                scope: "doctag",
                                match: "@examples",
                                starts: Mode(
                                    end: .re(RegexSource.lookahead(RegexSource.either(
                                        // end if another doc comment
                                        #"\n^#'\s*(?=@[a-zA-Z]+)"#,
                                        // or a line with no comment
                                        #"\n^(?!#')"#
                                    ))),
                                    endsParent: true
                                )
                            ),
                            Mode(
                                // Handle `@param` to highlight the parameter
                                // name following after.
                                scope: "doctag",
                                begin: "@param",
                                end: "$",
                                contains: [
                                    Mode(
                                        scope: "variable",
                                        variants: [
                                            Mode(match: .re(identRe)),
                                            Mode(match: #"`(?:\\.|[^`\\])+`"#),
                                        ],
                                        endsParent: true
                                    ),
                                ]
                            ),
                            Mode(scope: "doctag", match: "@[a-zA-Z]+"),
                            Mode(scope: "keyword", match: #"\\[a-zA-Z]+"#),
                        ]
                    },

                    CommonModes.hashCommentMode,

                    Mode(
                        scope: "string",
                        contains: [CommonModes.backslashEscape],
                        variants: [
                            Mode(begin: #"[rR]"(-*)\("#, end: #"\)(-*)""#, endSameAsBegin: true),
                            Mode(begin: #"[rR]"(-*)\{"#, end: #"\}(-*)""#, endSameAsBegin: true),
                            Mode(begin: #"[rR]"(-*)\["#, end: #"\](-*)""#, endSameAsBegin: true),
                            Mode(begin: #"[rR]'(-*)\("#, end: #"\)(-*)'"#, endSameAsBegin: true),
                            Mode(begin: #"[rR]'(-*)\{"#, end: #"\}(-*)'"#, endSameAsBegin: true),
                            Mode(begin: #"[rR]'(-*)\["#, end: #"\](-*)'"#, endSameAsBegin: true),
                            Mode(begin: "\"", end: "\"", relevance: 0),
                            Mode(begin: "'", end: "'", relevance: 0),
                        ]
                    ),

                    // Matching numbers immediately following punctuation and
                    // operators is tricky since we need to look at the
                    // character ahead of a number to ensure the number is not
                    // part of an identifier, and we cannot use negative
                    // look-behind assertions. So instead we explicitly handle
                    // all possible combinations of (operator|punctuation),
                    // number.
                    Mode(
                        variants: [
                            Mode(
                                scope: [1: "operator", 2: "number"],
                                match: [operatorsRe, numberTypesRe]
                            ),
                            Mode(
                                scope: [1: "operator", 2: "number"],
                                match: ["%[^%]*%", numberTypesRe]
                            ),
                            Mode(
                                scope: [1: "punctuation", 2: "number"],
                                match: [punctuationRe, numberTypesRe]
                            ),
                            Mode(
                                scope: [2: "number"],
                                match: [
                                    "[^a-zA-Z0-9._]|^", // not part of an identifier, or start of document
                                    numberTypesRe,
                                ]
                            ),
                        ],
                        relevance: 0
                    ),

                    // Operators/punctuation when they're not directly followed
                    // by numbers
                    Mode(
                        // Relevance boost for the most common assignment form.
                        scope: [3: "operator"],
                        match: [identRe, #"\s+"#, "<-", #"\s+"#]
                    ),

                    Mode(
                        scope: "operator",
                        variants: [
                            Mode(match: .re(operatorsRe)),
                            Mode(match: "%[^%]*%"),
                        ],
                        relevance: 0
                    ),

                    Mode(
                        scope: "punctuation",
                        match: .re(punctuationRe),
                        relevance: 0
                    ),

                    Mode(
                        // Escaped identifier
                        begin: "`",
                        end: "`",
                        contains: [Mode(begin: #"\\."#)]
                    ),
                ]
            )
        )
    }
}
