import Foundation

extension LanguageCatalog {
    /// CSS. Port of highlight.js `languages/css.js`.
    public static let css = LanguageDescriptor(name: "css") {
        let vendorPrefix = Mode(begin: #"-(webkit|moz|ms|o)-(?=[a-z])"#)
        let atModifiers = "and or not only"
        let atPropertyRe = #"@-?\w[\w]*(-\w+)*"# // @-webkit-keyframes
        let identRe = "[a-zA-Z-][a-zA-Z0-9_-]*"
        func strings() -> [Mode] {
            [CommonModes.aposStringMode, CommonModes.quoteStringMode]
        }

        return LanguageDefinition(
            name: "css",
            caseInsensitive: true,
            classNameAliases: [
                // for visual continuity with `tag {}` and because we
                // don't have a great class for this?
                "keyframePosition": "selector-tag",
            ],
            root: Mode(
                keywords: ["keyframePosition": "from to"],
                illegal: [#"[=|'\$]"#],
                contains: [
                    CommonModes.cBlockCommentMode,
                    vendorPrefix,
                    // to recognize keyframe 40% etc which are outside the
                    // scope of our attribute value mode
                    CssShared.cssNumberMode,
                    Mode(scope: "selector-id", begin: "#[A-Za-z0-9_-]+", relevance: 0),
                    Mode(scope: "selector-class", begin: .re("\\." + identRe), relevance: 0),
                    CssShared.attributeSelectorMode,
                    Mode(
                        scope: "selector-pseudo",
                        variants: [
                            Mode(begin: .re(":(" + CssShared.pseudoClasses.joined(separator: "|") + ")")),
                            Mode(begin: .re(":(:)?(" + CssShared.pseudoElements.joined(separator: "|") + ")")),
                        ]
                    ),
                    CssShared.cssVariable,
                    Mode(scope: "attribute", begin: .re("\\b(" + CssShared.attributes.joined(separator: "|") + ")\\b")),
                    // attribute values
                    Mode(
                        begin: ":",
                        end: "[;}{]",
                        contains: [
                            CommonModes.cBlockCommentMode,
                            CssShared.hexColor,
                            CssShared.important,
                            CssShared.cssNumberMode,
                        ] + strings() + [
                            // needed to highlight these as strings and to
                            // avoid issues with illegal characters that
                            // might be inside urls that would trigger the
                            // language's illegal stack
                            Mode(
                                begin: #"(url|data-uri)\("#,
                                end: #"\)"#,
                                keywords: ["built_in": "url data-uri"],
                                contains: strings() + [
                                    Mode(
                                        scope: "string",
                                        // any character other than `)` as in
                                        // `url()` will start a string, ended
                                        // by `)` from the parent mode
                                        begin: #"[^)]"#,
                                        excludeEnd: true,
                                        endsWithParent: true
                                    ),
                                ],
                                relevance: 0 // from keywords
                            ),
                            CssShared.functionDispatch,
                        ]
                    ),
                    Mode(
                        begin: .re(RegexSource.lookahead("@")),
                        end: "[{;]",
                        illegal: [":"], // break on Less variables @var: ...
                        contains: [
                            Mode(scope: "keyword", begin: .re(atPropertyRe)),
                            Mode(
                                begin: #"\s"#,
                                keywords: Keywords(
                                    pattern: "[a-z-]+",
                                    [
                                        "keyword": Keywords.Group(stringLiteral: atModifiers),
                                        "attribute": Keywords.Group(words: CssShared.mediaFeatures),
                                    ]
                                ),
                                contains: [
                                    Mode(scope: "attribute", begin: "[a-z-]+(?=:)"),
                                ] + strings() + [
                                    CssShared.cssNumberMode,
                                ],
                                relevance: 0,
                                excludeEnd: true,
                                endsWithParent: true
                            ),
                        ],
                        relevance: 0
                    ),
                    Mode(scope: "selector-tag", begin: .re("\\b(" + CssShared.tags.joined(separator: "|") + ")\\b")),
                ]
            )
        )
    }
}
