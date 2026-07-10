import Foundation

extension LanguageCatalog {
    /// HTML, XML. Port of highlight.js `languages/xml.js`.
    public static let xml = LanguageDescriptor(
        name: "xml",
        aliases: ["html", "xhtml", "rss", "atom", "xjb", "xsd", "xsl", "plist", "wsf", "svg"]
    ) {
        // Rely on the Unicode letter class for tag names (see the
        // upstream commentary about full XML NameChar support).
        let tagNameRe = #"[\p{L}_](?:[\p{L}0-9_.-]*:)?[\p{L}0-9_.-]*"#
        let xmlIdentRe = #"[\p{L}0-9._:-]+"#

        let xmlEntities = Mode(
            scope: "symbol",
            begin: #"&[a-z]+;|&#[0-9]+;|&#x[a-f0-9]+;"#
        )
        func xmlMetaKeywords() -> Mode {
            Mode(
                begin: #"\s"#,
                contains: [
                    Mode(scope: "keyword", begin: #"#?[a-z_][a-z1-9_-]+"#, illegal: [#"\n"#]),
                ]
            )
        }
        func xmlMetaParKeywords() -> Mode {
            let mode = xmlMetaKeywords()
            mode.begin = #"\("#
            mode.end = #"\)"#
            return mode
        }
        func aposMetaStringMode() -> Mode {
            let mode = CommonModes.aposStringMode
            mode.scope = "string"
            return mode
        }
        func quoteMetaStringMode() -> Mode {
            let mode = CommonModes.quoteStringMode
            mode.scope = "string"
            return mode
        }
        let tagInternals = Mode(
            keywords: nil,
            illegal: ["<"],
            contains: [
                Mode(scope: "attr", begin: .re(xmlIdentRe), relevance: 0),
                Mode(
                    begin: #"=\s*"#,
                    contains: [
                        Mode(
                            scope: "string",
                            variants: [
                                Mode(begin: "\"", end: "\"", contains: [xmlEntities]),
                                Mode(begin: "'", end: "'", contains: [xmlEntities]),
                                Mode(begin: #"[^\s"'=<>`]+"#),
                            ],
                            endsParent: true
                        ),
                    ],
                    relevance: 0
                ),
            ],
            relevance: 0,
            endsWithParent: true
        )

        return LanguageDefinition(
            name: "xml",
            aliases: ["html", "xhtml", "rss", "atom", "xjb", "xsd", "xsl", "plist", "wsf", "svg"],
            caseInsensitive: true,
            root: Mode(
                contains: [
                    Mode(
                        scope: "meta",
                        begin: #"<![a-z]"#,
                        end: ">",
                        contains: [
                            xmlMetaKeywords(),
                            quoteMetaStringMode(),
                            aposMetaStringMode(),
                            xmlMetaParKeywords(),
                            Mode(
                                begin: #"\["#,
                                end: #"\]"#,
                                contains: [
                                    Mode(
                                        scope: "meta",
                                        begin: #"<![a-z]"#,
                                        end: ">",
                                        contains: [
                                            xmlMetaKeywords(),
                                            xmlMetaParKeywords(),
                                            quoteMetaStringMode(),
                                            aposMetaStringMode(),
                                        ]
                                    ),
                                ]
                            ),
                        ],
                        relevance: 10
                    ),
                    CommonModes.comment("<!--", "-->") { $0.relevance = 10 },
                    Mode(begin: #"<!\[CDATA\["#, end: #"\]\]>"#, relevance: 10),
                    xmlEntities,
                    // XML processing instructions
                    Mode(
                        scope: "meta",
                        end: #"\?>"#,
                        variants: [
                            Mode(begin: #"<\?xml"#, contains: [quoteMetaStringMode()], relevance: 10),
                            Mode(begin: #"<\?[a-z][a-z0-9]+"#),
                        ]
                    ),
                    // <style>…</style> with embedded CSS
                    Mode(
                        scope: "tag",
                        begin: #"<style(?=\s|>)"#,
                        end: ">",
                        keywords: ["name": "style"],
                        contains: [tagInternals],
                        starts: Mode(
                            end: "</style>",
                            subLanguage: ["css", "xml"],
                            returnEnd: true
                        )
                    ),
                    // <script>…</script> with embedded JavaScript
                    Mode(
                        scope: "tag",
                        begin: #"<script(?=\s|>)"#,
                        end: ">",
                        keywords: ["name": "script"],
                        contains: [tagInternals],
                        starts: Mode(
                            end: "</script>",
                            subLanguage: ["javascript", "handlebars", "xml"],
                            returnEnd: true
                        )
                    ),
                    // JSX fragments
                    Mode(scope: "tag", begin: #"<>|</>"#),
                    // open tag
                    Mode(
                        scope: "tag",
                        begin: .re("<" + RegexSource.lookahead(tagNameRe + RegexSource.either(#"/>"#, ">", #"\s"#))),
                        end: #"/?>"#,
                        contains: [
                            Mode(
                                scope: "name",
                                begin: .re(tagNameRe),
                                starts: tagInternals,
                                relevance: 0
                            ),
                        ]
                    ),
                    // close tag
                    Mode(
                        scope: "tag",
                        begin: .re("</" + RegexSource.lookahead(tagNameRe + ">")),
                        contains: [
                            Mode(scope: "name", begin: .re(tagNameRe), relevance: 0),
                            Mode(begin: ">", relevance: 0, endsParent: true),
                        ]
                    ),
                ]
            )
        )
    }
}
