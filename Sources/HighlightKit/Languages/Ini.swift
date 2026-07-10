import Foundation

extension LanguageCatalog {
    /// TOML, also INI. Port of highlight.js `languages/ini.js`.
    public static let ini = LanguageDescriptor(name: "ini", aliases: ["toml"]) {
        let numbers = Mode(
            scope: "number",
            variants: [
                Mode(begin: #"([+-]+)?[\d]+_[\d_]+"#),
                Mode(begin: .re(CommonModes.numberRe)),
            ],
            relevance: 0
        )
        let comments = CommonModes.comment("", "") { mode in
            mode.variants = [
                Mode(begin: ";", end: "$"),
                Mode(begin: "#", end: "$"),
            ]
        }
        let variables = Mode(
            scope: "variable",
            variants: [
                Mode(begin: #"\$[\w\d"][\w\d_]*"#),
                Mode(begin: #"\$\{(.*?)\}"#),
            ]
        )
        let literals = Mode(
            scope: "literal",
            begin: #"\bon|off|true|false|yes|no\b"#
        )
        let strings = Mode(
            scope: "string",
            contains: [CommonModes.backslashEscape],
            variants: [
                Mode(begin: "'''", end: "'''", relevance: 10),
                Mode(begin: "\"\"\"", end: "\"\"\"", relevance: 10),
                Mode(begin: "\"", end: "\""),
                Mode(begin: "'", end: "'"),
            ]
        )
        let array = Mode(
            begin: #"\["#,
            end: #"\]"#,
            contains: [
                comments,
                literals,
                variables,
                strings,
                numbers,
                Mode.selfReference,
            ],
            relevance: 0
        )

        let bareKey = #"[A-Za-z0-9_-]+"#
        let quotedKeyDoubleQuote = #""(\\"|[^"])*""#
        let quotedKeySingleQuote = #"'[^']*'"#
        let anyKey = RegexSource.either(
            bareKey, quotedKeyDoubleQuote, quotedKeySingleQuote
        )
        let dottedKey = RegexSource.concat(
            anyKey, #"(\s*\.\s*"#, anyKey, ")*",
            RegexSource.lookahead(#"\s*=\s*[^#\s]"#)
        )

        return LanguageDefinition(
            name: "ini",
            aliases: ["toml"],
            caseInsensitive: true,
            root: Mode(
                illegal: [#"\S"#],
                contains: [
                    comments,
                    Mode(
                        scope: "section",
                        begin: #"\[+"#,
                        end: #"\]+"#
                    ),
                    Mode(
                        scope: "attr",
                        begin: .re(dottedKey),
                        starts: Mode(
                            end: "$",
                            contains: [
                                comments,
                                array,
                                literals,
                                variables,
                                strings,
                                numbers,
                            ]
                        )
                    ),
                ]
            )
        )
    }
}
