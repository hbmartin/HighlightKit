import Foundation

extension LanguageCatalog {
    /// Haskell. Port of highlight.js `languages/haskell.js`.
    public static let haskell = LanguageDescriptor(name: "haskell", aliases: ["hs"]) {
        /* See:
           - https://www.haskell.org/onlinereport/lexemes.html
           - https://downloads.haskell.org/ghc/9.0.1/docs/html/users_guide/exts/binary_literals.html
           - https://downloads.haskell.org/ghc/9.0.1/docs/html/users_guide/exts/numeric_underscores.html
           - https://downloads.haskell.org/ghc/9.0.1/docs/html/users_guide/exts/hex_float_literals.html
        */
        let decimalDigits = "([0-9]_*)+"
        let hexDigits = "([0-9a-fA-F]_*)+"
        let binaryDigits = "([01]_*)+"
        let octalDigits = "([0-7]_*)+"
        let ascSymbol = #"[!#$%&*+.\/<=>?@\\^~-]"#
        let uniSymbol = #"(\p{S}|\p{P})"# // Symbol or Punctuation
        let special = #"[(),;\[\]`|{}]"#
        let symbol = "(\(ascSymbol)|(?!(\(special)|[_:\"']))\(uniSymbol))"

        let comment = Mode(variants: [
            // Double dash forms a valid comment only if it's not part of
            // a legal lexeme (see the upstream commentary; a no-markup
            // rule before COMMENT handles the infix-operator case).
            CommonModes.comment("--+", "$"),
            CommonModes.comment(#"\{-"#, #"-\}"#) { $0.contains = [Mode.selfReference] },
        ])

        let pragma = Mode(
            scope: "meta",
            begin: #"\{-#"#,
            end: #"#-\}"#
        )

        let preprocessor = Mode(
            scope: "meta",
            begin: "^#",
            end: "$"
        )

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
                pragma,
                preprocessor,
                Mode(scope: "type", begin: #"\b[A-Z][\w]*(\((\.\.|,|\w+)\))?"#),
                { let m = CommonModes.titleMode; m.begin = #"[_a-z][\w']*"#; return m }(),
                comment,
            ]
        )

        let record = Mode(
            begin: #"\{"#,
            end: #"\}"#,
            contains: list.contains
        )

        let number = Mode(
            scope: "number",
            variants: [
                // decimal floating-point-literal (subsumes decimal-literal)
                Mode(match: .re("\\b(\(decimalDigits))(\\.(\(decimalDigits)))?" + "([eE][+-]?(\(decimalDigits)))?\\b")),
                // hexadecimal floating-point-literal (subsumes hexadecimal-literal)
                Mode(match: .re("\\b0[xX]_*(\(hexDigits))(\\.(\(hexDigits)))?" + "([pP][+-]?(\(decimalDigits)))?\\b")),
                // octal-literal
                Mode(match: .re("\\b0[oO](\(octalDigits))\\b")),
                // binary-literal
                Mode(match: .re("\\b0[bB](\(binaryDigits))\\b")),
            ],
            relevance: 0
        )

        return LanguageDefinition(
            name: "haskell",
            aliases: ["hs"],
            root: Mode(
                keywords: "let in if then else case of where do module import hiding qualified type data newtype deriving class instance as default infix infixl infixr foreign export ccall stdcall cplusplus jvm dotnet safe unsafe family forall mdo proc rec",
                contains: [
                    // Top-level constructions.
                    Mode(
                        beginKeywords: "module",
                        end: "where",
                        keywords: "module where",
                        illegal: [#"\W\.|;"#],
                        contains: [
                            list,
                            comment,
                        ]
                    ),
                    Mode(
                        begin: #"\bimport\b"#,
                        end: "$",
                        keywords: "import qualified as hiding",
                        illegal: [#"\W\.|;"#],
                        contains: [
                            list,
                            comment,
                        ]
                    ),
                    Mode(
                        scope: "class",
                        begin: #"^(\s*)?(class|instance)\b"#,
                        end: "where",
                        keywords: "class family instance where",
                        contains: [
                            constructor,
                            list,
                            comment,
                        ]
                    ),
                    Mode(
                        scope: "class",
                        begin: #"\b(data|(new)?type)\b"#,
                        end: "$",
                        keywords: "data family type newtype deriving",
                        contains: [
                            pragma,
                            constructor,
                            list,
                            record,
                            comment,
                        ]
                    ),
                    Mode(
                        beginKeywords: "default",
                        end: "$",
                        contains: [
                            constructor,
                            list,
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
                        begin: #"\bforeign\b"#,
                        end: "$",
                        keywords: "foreign import export ccall stdcall cplusplus jvm dotnet safe unsafe",
                        contains: [
                            constructor,
                            CommonModes.quoteStringMode,
                            comment,
                        ]
                    ),
                    Mode(
                        scope: "meta",
                        begin: #"#!\/usr\/bin\/env runhaskell"#,
                        end: "$"
                    ),
                    // "Whitespaces".
                    pragma,
                    preprocessor,

                    // Literals and names.

                    // Single characters.
                    Mode(
                        scope: "string",
                        begin: #"'(?=\\?.')"#,
                        end: "'",
                        contains: [
                            Mode(scope: "char.escape", match: #"\\."#),
                        ]
                    ),
                    CommonModes.quoteStringMode,
                    number,
                    constructor,
                    { let m = CommonModes.titleMode; m.begin = #"^[_a-z][\w']*"#; return m }(),
                    // No markup, prevents infix operators from being recognized as comments.
                    Mode(begin: .re("(?!-)\(symbol)--+|--+(?!-)\(symbol)")),
                    comment,
                    // No markup, relevance booster
                    Mode(begin: "->|<-"),
                ]
            )
        )
    }
}
