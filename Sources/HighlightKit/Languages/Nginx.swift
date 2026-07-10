import Foundation

extension LanguageCatalog {
    /// Nginx config. Port of highlight.js `languages/nginx.js`.
    public static let nginx = LanguageDescriptor(name: "nginx", aliases: ["nginxconf"]) {
        let variable = Mode(
            scope: "variable",
            variants: [
                Mode(begin: #"\$\d+"#),
                Mode(begin: #"\$\{\w+\}"#),
                Mode(begin: .re(RegexSource.concat(#"[$@]"#, CommonModes.underscoreIdentRe))),
            ]
        )
        let literals = [
            "on",
            "off",
            "yes",
            "no",
            "true",
            "false",
            "none",
            "blocked",
            "debug",
            "info",
            "notice",
            "warn",
            "error",
            "crit",
            "select",
            "break",
            "last",
            "permanent",
            "redirect",
            "kqueue",
            "rtsig",
            "epoll",
            "poll",
            "/dev/poll",
        ]
        let defaultMode = Mode(
            keywords: Keywords(
                pattern: #"[a-z_]{2,}|\/dev\/poll"#,
                ["literal": Keywords.Group(words: literals)]
            ),
            illegal: ["=>"],
            contains: [
                CommonModes.hashCommentMode,
                Mode(
                    scope: "string",
                    contains: [
                        CommonModes.backslashEscape,
                        variable,
                    ],
                    variants: [
                        Mode(begin: "\"", end: "\""),
                        Mode(begin: "'", end: "'"),
                    ]
                ),
                // this swallows entire URLs to avoid detecting numbers within
                Mode(
                    begin: "([a-z]+):/",
                    end: #"\s"#,
                    contains: [variable],
                    excludeEnd: true,
                    endsWithParent: true
                ),
                Mode(
                    scope: "regexp",
                    contains: [
                        CommonModes.backslashEscape,
                        variable,
                    ],
                    variants: [
                        Mode(begin: #"\s\^"#, end: #"\s|\{|;"#, returnEnd: true),
                        // regexp locations (~, ~*)
                        Mode(begin: #"~\*?\s+"#, end: #"\s|\{|;"#, returnEnd: true),
                        // *.example.com
                        Mode(begin: #"\*(\.[a-z\-]+)+"#),
                        // sub.example.*
                        Mode(begin: #"([a-z\-]+\.)+\*"#),
                    ]
                ),
                // IP
                Mode(
                    scope: "number",
                    begin: #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d{1,5})?\b"#
                ),
                // units
                Mode(
                    scope: "number",
                    begin: #"\b\d+[kKmMgGdshdwy]?\b"#,
                    relevance: 0
                ),
                variable,
            ],
            relevance: 0,
            endsWithParent: true
        )

        return LanguageDefinition(
            name: "nginx",
            aliases: ["nginxconf"],
            root: Mode(
                illegal: [#"[^\s\}\{]"#],
                contains: [
                    CommonModes.hashCommentMode,
                    Mode(
                        beginKeywords: "upstream location",
                        end: #";|\{"#,
                        keywords: ["section": "upstream location"],
                        contains: defaultMode.contains
                    ),
                    Mode(
                        scope: "section",
                        begin: .re(RegexSource.concat(
                            CommonModes.underscoreIdentRe + RegexSource.lookahead(#"\s+\{"#)
                        )),
                        relevance: 0
                    ),
                    Mode(
                        begin: .re(RegexSource.lookahead(CommonModes.underscoreIdentRe + #"\s"#)),
                        end: #";|\{"#,
                        contains: [
                            Mode(
                                scope: "attribute",
                                begin: .re(CommonModes.underscoreIdentRe),
                                starts: defaultMode
                            ),
                        ],
                        relevance: 0
                    ),
                ]
            )
        )
    }
}
