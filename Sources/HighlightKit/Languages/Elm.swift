import Foundation

extension LanguageCatalog {
    /// Elm. Port of highlight.js `languages/elm.js`.
    public static let elm = LanguageDescriptor(name: "elm") {
        let comment = Mode(variants: [
            CommonModes.comment("--", "$"),
            CommonModes.comment(#"\{-"#, #"-\}"#) { $0.contains = [Mode.selfReference] },
        ])

        let constructor = Mode(
            scope: "type",
            begin: #"\b[A-Z][\w']*"#, // TODO: other constructors (built-in, infix).
            relevance: 0
        )

        let list = Mode(
            begin: #"\("#,
            end: #"\)"#,
            illegal: ["\""],
            contains: [
                Mode(scope: "type", begin: #"\b[A-Z][\w]*(\((\.\.|,|\w+)\))?"#),
                comment,
            ]
        )

        let record = Mode(
            begin: #"\{"#,
            end: #"\}"#,
            contains: list.contains
        )

        let character = Mode(
            scope: "string",
            begin: #"'\\?."#,
            end: "'",
            illegal: ["."]
        )

        let keywords = [
            "let",
            "in",
            "if",
            "then",
            "else",
            "case",
            "of",
            "where",
            "module",
            "import",
            "exposing",
            "type",
            "alias",
            "as",
            "infix",
            "infixl",
            "infixr",
            "port",
            "effect",
            "command",
            "subscription",
        ]

        return LanguageDefinition(
            name: "elm",
            root: Mode(
                keywords: Keywords(keyword: Keywords.Group(words: keywords)),
                illegal: [";"],
                contains: [
                    // Top-level constructions.
                    Mode(
                        beginKeywords: "port effect module",
                        end: "exposing",
                        keywords: "port effect module where command subscription exposing",
                        illegal: [#"\W\.|;"#],
                        contains: [
                            list,
                            comment,
                        ]
                    ),
                    Mode(
                        begin: "import",
                        end: "$",
                        keywords: "import as exposing",
                        illegal: [#"\W\.|;"#],
                        contains: [
                            list,
                            comment,
                        ]
                    ),
                    Mode(
                        begin: "type",
                        end: "$",
                        keywords: "type alias",
                        contains: [
                            constructor,
                            list,
                            record,
                            comment,
                        ]
                    ),
                    Mode(
                        beginKeywords: "infix infixl infixr",
                        end: "$",
                        contains: [
                            CommonModes.cNumberMode,
                            comment,
                        ]
                    ),
                    Mode(
                        begin: "port",
                        end: "$",
                        keywords: "port",
                        contains: [comment]
                    ),

                    // Literals and names.
                    character,
                    CommonModes.quoteStringMode,
                    CommonModes.cNumberMode,
                    constructor,
                    { let m = CommonModes.titleMode; m.begin = #"^[_a-z][\w']*"#; return m }(),
                    comment,

                    // No markup, relevance booster
                    Mode(begin: "->|<-"),
                ]
            )
        )
    }
}
