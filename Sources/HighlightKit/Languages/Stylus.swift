import Foundation

extension LanguageCatalog {
    /// Stylus. Port of highlight.js `languages/stylus.js`.
    public static let stylus = LanguageDescriptor(name: "stylus", aliases: ["styl"]) {
        // const modes = css.MODES(hljs) — each mode created once, shared.
        let important = CssShared.important
        let hexColor = CssShared.hexColor
        let functionDispatch = CssShared.functionDispatch
        let attributeSelectorMode = CssShared.attributeSelectorMode
        let cssNumberMode = CssShared.cssNumberMode
        let cssVariable = CssShared.cssVariable

        let atModifiers = "and or not only"
        let variable = Mode(
            scope: "variable",
            begin: .re("\\$" + CommonModes.identRe)
        )

        let atKeywords = [
            "charset",
            "css",
            "debug",
            "extend",
            "font-face",
            "for",
            "import",
            "include",
            "keyframes",
            "media",
            "mixin",
            "page",
            "warn",
            "while",
        ]

        // JS `(?=[.\s\n[:,(])` — the bare `[` inside the class must be
        // escaped for ICU.
        let lookaheadTagEnd = #"(?=[.\s\n\[:,(])"#

        // illegals
        let illegal = [
            #"\?"#,
            #"(\bReturn\b)"#, // monkey
            #"(\bEnd\b)"#, // monkey
            #"(\bend\b)"#, // vbscript
            #"(\bdef\b)"#, // gradle
            ";", // a whole lot of languages
            #"#\s"#, // markdown
            #"\*\s"#, // markdown
            #"===\s"#, // markdown
            #"\|"#,
            "%", // prolog
        ]

        return LanguageDefinition(
            name: "stylus",
            aliases: ["styl"],
            root: Mode(
                keywords: "if else for in",
                illegal: ["(" + illegal.joined(separator: "|") + ")"],
                contains: [
                    // strings
                    CommonModes.quoteStringMode,
                    CommonModes.aposStringMode,

                    // comments
                    CommonModes.cLineCommentMode,
                    CommonModes.cBlockCommentMode,

                    // hex colors
                    hexColor,

                    // class tag
                    Mode(
                        scope: "selector-class",
                        begin: .re("\\.[a-zA-Z][a-zA-Z0-9_-]*" + lookaheadTagEnd)
                    ),

                    // id tag
                    Mode(
                        scope: "selector-id",
                        begin: .re("#[a-zA-Z][a-zA-Z0-9_-]*" + lookaheadTagEnd)
                    ),

                    // tags
                    Mode(
                        scope: "selector-tag",
                        begin: .re("\\b(" + CssShared.tags.joined(separator: "|") + ")" + lookaheadTagEnd)
                    ),

                    // psuedo selectors
                    Mode(
                        scope: "selector-pseudo",
                        begin: .re("&?:(" + CssShared.pseudoClasses.joined(separator: "|") + ")" + lookaheadTagEnd)
                    ),
                    Mode(
                        scope: "selector-pseudo",
                        begin: .re("&?:(:)?(" + CssShared.pseudoElements.joined(separator: "|") + ")" + lookaheadTagEnd)
                    ),

                    attributeSelectorMode,

                    Mode(
                        scope: "keyword",
                        begin: "@media",
                        starts: Mode(
                            end: "[{;}]",
                            keywords: Keywords(
                                pattern: "[a-z-]+",
                                [
                                    "keyword": Keywords.Group(stringLiteral: atModifiers),
                                    "attribute": Keywords.Group(words: CssShared.mediaFeatures),
                                ]
                            ),
                            contains: [cssNumberMode]
                        )
                    ),

                    // @ keywords
                    Mode(
                        scope: "keyword",
                        begin: .re("@((-(o|moz|ms|webkit)-)?(" + atKeywords.joined(separator: "|") + "))\\b")
                    ),

                    // variables
                    variable,

                    // dimension
                    cssNumberMode,

                    // functions
                    //  - only from beginning of line + whitespace
                    Mode(
                        scope: "function",
                        begin: #"^[a-zA-Z][a-zA-Z0-9_-]*\(.*\)"#,
                        illegal: [#"[\n]"#],
                        contains: [
                            Mode(
                                scope: "title",
                                begin: #"\b[a-zA-Z][a-zA-Z0-9_-]*"#
                            ),
                            Mode(
                                scope: "params",
                                begin: #"\("#,
                                end: #"\)"#,
                                contains: [
                                    hexColor,
                                    variable,
                                    CommonModes.aposStringMode,
                                    cssNumberMode,
                                    CommonModes.quoteStringMode,
                                ]
                            ),
                        ],
                        returnBegin: true
                    ),

                    // css variables
                    cssVariable,

                    // attributes
                    //  - only from beginning of line + whitespace
                    //  - must have whitespace after it
                    Mode(
                        scope: "attribute",
                        begin: .re("\\b(" + CssShared.attributes.joined(separator: "|") + ")\\b"),
                        starts: Mode(
                            // value container
                            end: ";|$",
                            illegal: [#"\."#],
                            contains: [
                                hexColor,
                                variable,
                                CommonModes.aposStringMode,
                                CommonModes.quoteStringMode,
                                cssNumberMode,
                                CommonModes.cBlockCommentMode,
                                important,
                                functionDispatch,
                            ],
                            relevance: 0
                        )
                    ),
                    functionDispatch,
                ]
            )
        )
    }
}
