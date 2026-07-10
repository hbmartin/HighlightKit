import Foundation

extension LanguageCatalog {
    /// SCSS. Port of highlight.js `languages/scss.js`.
    public static let scss = LanguageDescriptor(name: "scss") {
        // const modes = css.MODES(hljs) — each mode created once, shared.
        let important = CssShared.important
        let blockComment = CommonModes.cBlockCommentMode
        let hexColor = CssShared.hexColor
        let functionDispatch = CssShared.functionDispatch
        let attributeSelectorMode = CssShared.attributeSelectorMode
        let cssNumberMode = CssShared.cssNumberMode
        let cssVariable = CssShared.cssVariable

        let atIdentifier = "@[a-z-]+" // @font-face
        let atModifiers = "and or not only"
        let identRe = "[a-zA-Z-][a-zA-Z0-9_-]*"
        let variable = Mode(
            scope: "variable",
            begin: .re("(\\$" + identRe + ")\\b"),
            relevance: 0
        )

        return LanguageDefinition(
            name: "scss",
            caseInsensitive: true,
            root: Mode(
                illegal: ["[=/|']"],
                contains: [
                    CommonModes.cLineCommentMode,
                    blockComment,
                    // to recognize keyframe 40% etc which are outside the scope of our
                    // attribute value mode
                    cssNumberMode,
                    Mode(
                        scope: "selector-id",
                        begin: "#[A-Za-z0-9_-]+",
                        relevance: 0
                    ),
                    Mode(
                        scope: "selector-class",
                        begin: #"\.[A-Za-z0-9_-]+"#,
                        relevance: 0
                    ),
                    attributeSelectorMode,
                    Mode(
                        scope: "selector-tag",
                        begin: .re("\\b(" + CssShared.tags.joined(separator: "|") + ")\\b"),
                        // was there, before, but why?
                        relevance: 0
                    ),
                    Mode(
                        scope: "selector-pseudo",
                        begin: .re(":(" + CssShared.pseudoClasses.joined(separator: "|") + ")")
                    ),
                    Mode(
                        scope: "selector-pseudo",
                        begin: .re(":(:)?(" + CssShared.pseudoElements.joined(separator: "|") + ")")
                    ),
                    variable,
                    Mode( // pseudo-selector params
                        begin: #"\("#,
                        end: #"\)"#,
                        contains: [cssNumberMode]
                    ),
                    cssVariable,
                    Mode(
                        scope: "attribute",
                        begin: .re("\\b(" + CssShared.attributes.joined(separator: "|") + ")\\b")
                    ),
                    Mode(begin: #"\b(whitespace|wait|w-resize|visible|vertical-text|vertical-ideographic|uppercase|upper-roman|upper-alpha|underline|transparent|top|thin|thick|text|text-top|text-bottom|tb-rl|table-header-group|table-footer-group|sw-resize|super|strict|static|square|solid|small-caps|separate|se-resize|scroll|s-resize|rtl|row-resize|ridge|right|repeat|repeat-y|repeat-x|relative|progress|pointer|overline|outside|outset|oblique|nowrap|not-allowed|normal|none|nw-resize|no-repeat|no-drop|newspaper|ne-resize|n-resize|move|middle|medium|ltr|lr-tb|lowercase|lower-roman|lower-alpha|loose|list-item|line|line-through|line-edge|lighter|left|keep-all|justify|italic|inter-word|inter-ideograph|inside|inset|inline|inline-block|inherit|inactive|ideograph-space|ideograph-parenthesis|ideograph-numeric|ideograph-alpha|horizontal|hidden|help|hand|groove|fixed|ellipsis|e-resize|double|dotted|distribute|distribute-space|distribute-letter|distribute-all-lines|disc|disabled|default|decimal|dashed|crosshair|collapse|col-resize|circle|char|center|capitalize|break-word|break-all|bottom|both|bolder|bold|block|bidi-override|below|baseline|auto|always|all-scroll|absolute|table|table-cell)\b"#),
                    Mode(
                        begin: ":",
                        end: "[;}{]",
                        contains: [
                            blockComment,
                            variable,
                            hexColor,
                            cssNumberMode,
                            CommonModes.quoteStringMode,
                            CommonModes.aposStringMode,
                            important,
                            functionDispatch,
                        ],
                        relevance: 0
                    ),
                    // matching these here allows us to treat them more like regular CSS
                    // rules so everything between the {} gets regular rule highlighting,
                    // which is what we want for page and font-face
                    Mode(
                        begin: "@(page|font-face)",
                        keywords: Keywords(
                            pattern: atIdentifier,
                            ["keyword": "@page @font-face"]
                        )
                    ),
                    Mode(
                        begin: "@",
                        end: "[{;]",
                        keywords: Keywords(
                            pattern: "[a-z-]+",
                            [
                                "keyword": Keywords.Group(stringLiteral: atModifiers),
                                "attribute": Keywords.Group(words: CssShared.mediaFeatures),
                            ]
                        ),
                        contains: [
                            Mode(scope: "keyword", begin: .re(atIdentifier)),
                            Mode(scope: "attribute", begin: "[a-z-]+(?=:)"),
                            variable,
                            CommonModes.quoteStringMode,
                            CommonModes.aposStringMode,
                            hexColor,
                            cssNumberMode,
                        ],
                        returnBegin: true
                    ),
                    functionDispatch,
                ]
            )
        )
    }
}
