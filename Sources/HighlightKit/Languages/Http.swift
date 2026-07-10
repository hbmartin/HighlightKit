import Foundation

extension LanguageCatalog {
    /// HTTP. Port of highlight.js `languages/http.js`.
    public static let http = LanguageDescriptor(name: "http", aliases: ["https"]) {
        let version = "HTTP/([32]|1\\.[01])"
        let headerName = "[A-Za-z][A-Za-z0-9-]*"
        let header = Mode(
            scope: "attribute",
            begin: .re(RegexSource.concat("^", headerName, "(?=\\:\\s)")),
            starts: Mode(contains: [
                Mode(
                    scope: "punctuation",
                    begin: ": ",
                    starts: Mode(end: "$", relevance: 0),
                    relevance: 0
                ),
            ])
        )
        let headersAndBody: [Mode] = [
            header,
            Mode(
                begin: "\\n\\n",
                starts: Mode(
                    subLanguage: [],
                    endsWithParent: true
                )
            ),
        ]

        return LanguageDefinition(
            name: "http",
            aliases: ["https"],
            root: Mode(
                illegal: ["\\S"],
                contains: [
                    // response
                    Mode(
                        begin: .re("^(?=" + version + " \\d{3})"),
                        end: "$",
                        contains: [
                            Mode(scope: "meta", begin: .re(version)),
                            Mode(scope: "number", begin: "\\b\\d{3}\\b"),
                        ],
                        starts: Mode(
                            end: "\\b\\B",
                            illegal: ["\\S"],
                            contains: headersAndBody
                        )
                    ),
                    // request
                    Mode(
                        begin: .re("(?=^[A-Z]+ (.*?) " + version + "$)"),
                        end: "$",
                        contains: [
                            Mode(
                                scope: "string",
                                begin: " ",
                                end: " ",
                                excludeBegin: true,
                                excludeEnd: true
                            ),
                            Mode(scope: "meta", begin: .re(version)),
                            Mode(scope: "keyword", begin: "[A-Z]+"),
                        ],
                        starts: Mode(
                            end: "\\b\\B",
                            illegal: ["\\S"],
                            contains: headersAndBody
                        )
                    ),
                    // to allow headers to work even without a preamble
                    header.copied { $0.relevance = 0 },
                ]
            )
        )
    }
}
