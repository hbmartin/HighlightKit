import Foundation

extension LanguageCatalog {
    /// Apache config. Port of highlight.js `languages/apache.js`.
    public static let apache = LanguageDescriptor(name: "apache", aliases: ["apacheconf"]) {
        let numberRef = Mode(
            scope: "number",
            begin: #"[$%]\d+"#
        )
        let number = Mode(
            scope: "number",
            begin: #"\b\d+"#
        )
        let ipAddress = Mode(
            scope: "number",
            begin: #"\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(:\d{1,5})?"#
        )
        let portNumber = Mode(
            scope: "number",
            begin: #":\d{1,5}"#
        )
        return LanguageDefinition(
            name: "apache",
            aliases: ["apacheconf"],
            caseInsensitive: true,
            root: Mode(
                illegal: [#"\S"#],
                contains: [
                    CommonModes.hashCommentMode,
                    Mode(
                        scope: "section",
                        begin: "</?",
                        end: ">",
                        contains: [
                            ipAddress,
                            portNumber,
                            // low relevance prevents us from claming XML/HTML
                            // where this rule would match strings inside of
                            // XML tags
                            {
                                let m = CommonModes.quoteStringMode
                                m.relevance = 0
                                return m
                            }(),
                        ]
                    ),
                    Mode(
                        scope: "attribute",
                        begin: #"\w+"#,
                        // keywords aren’t needed for highlighting per se,
                        // they only boost relevance for a very generally
                        // defined mode (starts with a word, ends with
                        // line-end
                        keywords: [
                            "_": [
                                "order",
                                "deny",
                                "allow",
                                "setenv",
                                "rewriterule",
                                "rewriteengine",
                                "rewritecond",
                                "documentroot",
                                "sethandler",
                                "errordocument",
                                "loadmodule",
                                "options",
                                "header",
                                "listen",
                                "serverroot",
                                "servername",
                            ],
                        ],
                        starts: Mode(
                            end: "$",
                            keywords: ["literal": "on off all deny allow"],
                            contains: [
                                Mode(
                                    scope: "punctuation",
                                    match: #"\\\n"#
                                ),
                                Mode(
                                    scope: "meta",
                                    begin: #"\s\["#,
                                    end: #"\]$"#
                                ),
                                Mode(
                                    scope: "variable",
                                    begin: #"[\$%]\{"#,
                                    end: #"\}"#,
                                    contains: [
                                        Mode.selfReference,
                                        numberRef,
                                    ]
                                ),
                                ipAddress,
                                number,
                                CommonModes.quoteStringMode,
                            ],
                            relevance: 0
                        ),
                        relevance: 0
                    ),
                ]
            )
        )
    }
}
