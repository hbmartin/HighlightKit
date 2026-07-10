import Foundation

extension LanguageCatalog {
    /// .properties. Port of highlight.js `languages/properties.js`.
    public static let properties = LanguageDescriptor(name: "properties") {
        // whitespaces: space, tab, formfeed
        let ws0 = #"[ \t\f]*"#
        let ws1 = #"[ \t\f]+"#
        // delimiter
        let equalDelim = ws0 + "[:=]" + ws0
        let wsDelim = ws1
        let delim = "(" + equalDelim + "|" + wsDelim + ")"
        let key = #"([^\\:= \t\f\n]|\\.)+"#

        let delimAndValue = Mode(
            // skip DELIM
            end: .re(delim),
            starts: Mode(
                // value: everything until end of line (again, taking into
                // account backslashes)
                scope: "string",
                end: "$",
                contains: [
                    Mode(begin: #"\\\\"#),
                    Mode(begin: #"\\\n"#),
                ],
                relevance: 0
            ),
            relevance: 0
        )

        return LanguageDefinition(
            name: "properties",
            caseInsensitive: true,
            disableAutodetect: true,
            root: Mode(
                illegal: [#"\S"#],
                contains: [
                    CommonModes.comment(#"^\s*[!#]"#, "$"),
                    // key: everything until whitespace or = or : (taking
                    // into account backslashes) — case of a key-value pair
                    Mode(
                        contains: [
                            Mode(
                                scope: "attr",
                                begin: .re(key),
                                endsParent: true
                            ),
                        ],
                        variants: [
                            Mode(begin: .re(key + equalDelim)),
                            Mode(begin: .re(key + wsDelim)),
                        ],
                        starts: delimAndValue,
                        returnBegin: true
                    ),
                    // case of an empty key
                    Mode(
                        scope: "attr",
                        begin: .re(key + ws0 + "$")
                    ),
                ]
            )
        )
    }
}
