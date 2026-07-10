import Foundation

extension LanguageCatalog {
    /// Less. Port of highlight.js `languages/less.js`.
    public static let less = LanguageDescriptor(name: "less") {
        // const modes = css.MODES(hljs) — each mode created once, shared.
        let important = CssShared.important
        let hexColor = CssShared.hexColor
        let functionDispatch = CssShared.functionDispatch
        let attributeSelectorMode = CssShared.attributeSelectorMode
        let cssNumberMode = CssShared.cssNumberMode
        let cssVariable = CssShared.cssVariable
        let cLineCommentMode = CommonModes.cLineCommentMode
        let cBlockCommentMode = CommonModes.cBlockCommentMode

        let atModifiers = "and or not only"
        let identRe = #"[\w-]+"# // yes, Less identifiers may begin with a digit
        let interpIdentRe = "(" + identRe + #"|@\{"# + identRe + #"\})"#

        /* Generic Modes */

        func stringMode(_ c: String) -> Mode {
            // Less strings are not multiline (also include '~' for more
            // consistent coloring of "escaped" strings)
            Mode(scope: "string", begin: .re("~?" + c + ".*?" + c))
        }

        func identMode(_ name: String, _ begin: String, _ relevance: Double? = nil) -> Mode {
            Mode(scope: .name(name), begin: .re(begin), relevance: relevance)
        }

        let atKeywords = Keywords(
            pattern: "[a-z-]+",
            [
                "keyword": Keywords.Group(stringLiteral: atModifiers),
                "attribute": Keywords.Group(words: CssShared.mediaFeatures),
            ]
        )

        let parensMode = Mode(
            // used only to properly balance nested parens inside mixin call,
            // def. arg list
            begin: #"\("#,
            end: #"\)"#,
            keywords: atKeywords,
            relevance: 0
        ) // contains: VALUE_MODES — assigned below (recursive)

        // generic Less highlighter (used almost everywhere except selectors):
        let valueModes: [Mode] = [
            cLineCommentMode,
            cBlockCommentMode,
            stringMode("'"),
            stringMode("\""),
            cssNumberMode, // fixme: it does not include dot for numbers like .5em :(
            Mode(
                begin: #"(url|data-uri)\("#,
                starts: Mode(
                    scope: "string",
                    end: #"[\)\n]"#,
                    excludeEnd: true
                )
            ),
            hexColor,
            parensMode,
            identMode("variable", "@@?" + identRe, 10),
            identMode("variable", #"@\{"# + identRe + #"\}"#),
            identMode("built_in", "~?`[^`]*?`"), // inline javascript (or whatever host language) *multiline* string
            Mode( // @media features (it's here to not duplicate things in AT_RULE_MODE with extra PARENS_MODE overriding):
                scope: "attribute",
                begin: .re(identRe + #"\s*:"#),
                end: ":",
                excludeEnd: true,
                returnBegin: true
            ),
            important,
            Mode(beginKeywords: "and not"),
            functionDispatch,
        ]
        parensMode.contains = valueModes

        let rulesetsBlock = Mode(
            begin: #"\{"#,
            end: #"\}"#
        ) // contains: RULES — assigned below (recursive)
        let valueWithRulesets = valueModes + [rulesetsBlock]

        let mixinGuardMode = Mode(
            beginKeywords: "when",
            // using this form to override VALUE's 'function' match
            contains: [Mode(beginKeywords: "and not")] + valueModes,
            endsWithParent: true
        )

        /* Rule-Level Modes */

        let ruleMode = Mode(
            begin: .re(interpIdentRe + #"\s*:"#),
            end: "[;}]",
            contains: [
                Mode(begin: "-(webkit|moz|ms|o)-"),
                cssVariable,
                Mode(
                    scope: "attribute",
                    begin: .re("\\b(" + CssShared.attributes.joined(separator: "|") + ")\\b"),
                    end: "(?=:)",
                    starts: Mode(
                        illegal: ["[<=$]"],
                        contains: valueModes,
                        relevance: 0,
                        endsWithParent: true
                    )
                ),
            ],
            relevance: 0,
            returnBegin: true
        )

        let atRuleMode = Mode(
            scope: "keyword",
            begin: #"@(import|media|charset|font-face|(-[a-z]+-)?keyframes|supports|document|namespace|page|viewport|host)\b"#,
            starts: Mode(
                end: "[;{}]",
                keywords: atKeywords,
                contains: valueModes,
                relevance: 0,
                returnEnd: true
            )
        )

        // variable definitions and calls
        let varRuleMode = Mode(
            scope: "variable",
            variants: [
                // using more strict pattern for higher relevance to increase
                // chances of Less detection.
                // this is *the only* Less specific statement used in most of the
                // sources, so...
                // (we'll still often loose to the css-parser unless there's '//'
                // comment, simply because 1 variable just can't beat 99
                // properties :)
                Mode(begin: .re("@" + identRe + #"\s*:"#), relevance: 15),
                Mode(begin: .re("@" + identRe)),
            ],
            starts: Mode(
                end: "[;}]",
                contains: valueWithRulesets,
                returnEnd: true
            )
        )

        let selectorMode = Mode(
            // first parse unambiguous selectors (i.e. those not starting with tag)
            // then fall into the scary lookahead-discriminator variant.
            // this mode also handles mixin definitions and calls
            illegal: ["[<='$\"]"],
            contains: [
                cLineCommentMode,
                cBlockCommentMode,
                mixinGuardMode,
                identMode("keyword", "all\\b"),
                identMode("variable", #"@\{"# + identRe + #"\}"#), // otherwise it's identified as tag
                Mode(
                    scope: "selector-tag",
                    begin: .re("\\b(" + CssShared.tags.joined(separator: "|") + ")\\b")
                ),
                cssNumberMode,
                identMode("selector-tag", interpIdentRe, 0),
                identMode("selector-id", "#" + interpIdentRe),
                identMode("selector-class", "\\." + interpIdentRe, 0),
                identMode("selector-tag", "&", 0),
                attributeSelectorMode,
                Mode(
                    scope: "selector-pseudo",
                    begin: .re(":(" + CssShared.pseudoClasses.joined(separator: "|") + ")")
                ),
                Mode(
                    scope: "selector-pseudo",
                    begin: .re(":(:)?(" + CssShared.pseudoElements.joined(separator: "|") + ")")
                ),
                Mode( // argument list of parametric mixins
                    begin: #"\("#,
                    end: #"\)"#,
                    contains: valueWithRulesets,
                    relevance: 0
                ),
                Mode(begin: "!important"), // eat !important after mixin call or it will be colored as tag
                functionDispatch,
            ],
            variants: [
                Mode(
                    begin: #"[\.#:&\[>]"#,
                    end: "[;{}]" // mixin calls end with ';'
                ),
                Mode(
                    begin: .re(interpIdentRe),
                    end: #"\{"#
                ),
            ],
            relevance: 0,
            returnBegin: true,
            returnEnd: true
        )

        let pseudoSelectorMode = Mode(
            begin: .re(identRe + ":(:)?(" + CssShared.pseudoSelectors.joined(separator: "|") + ")"),
            contains: [selectorMode],
            returnBegin: true
        )

        let rules: [Mode] = [
            cLineCommentMode,
            cBlockCommentMode,
            atRuleMode,
            varRuleMode,
            pseudoSelectorMode,
            ruleMode,
            selectorMode,
            mixinGuardMode,
            functionDispatch,
        ]
        rulesetsBlock.contains = rules

        return LanguageDefinition(
            name: "less",
            caseInsensitive: true,
            root: Mode(
                illegal: ["[=>'/<($\"]"],
                contains: rules
            )
        )
    }
}
