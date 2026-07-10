import Foundation

extension LanguageCatalog {
    /// Leaf. Port of highlight.js `languages/leaf.js`.
    public static let leaf = LanguageDescriptor(name: "leaf") {
        let ident = #"([A-Za-z_][A-Za-z_0-9]*)?"#
        let literals = ["true", "false", "in"]
        let params = Mode(
            scope: "params",
            begin: #"\("#,
            end: #"\)(?=\:?)"#,
            contains: [
                Mode(
                    scope: "string",
                    begin: "\"",
                    end: "\""
                ),
                Mode(
                    scope: "keyword",
                    match: .re(literals.joined(separator: "|"))
                ),
                Mode(
                    scope: "variable",
                    match: "[A-Za-z_][A-Za-z_0-9]*"
                ),
                Mode(
                    scope: "operator",
                    match: #"\+|\-|\*|\/|\%|\=\=|\=|\!|\>|\<|\&\&|\|\|"#
                ),
            ],
            relevance: 7,
            endsParent: true
        )
        let insideDispatch = Mode(
            scope: [1: "keyword"],
            match: [
                ident,
                #"(?=\()"#,
            ],
            contains: [params]
        )
        params.contains?.insert(insideDispatch, at: 0)
        return LanguageDefinition(
            name: "leaf",
            root: Mode(
                contains: [
                    // #ident():
                    Mode(
                        scope: [
                            1: "punctuation",
                            2: "keyword",
                        ],
                        match: [
                            "#+",
                            ident,
                            #"(?=\()"#,
                        ],
                        contains: [
                            params
                        ],
                        // will start up after the ending `)` match from line ~44
                        // just to grab the trailing `:` if we can match it
                        starts: Mode(
                            contains: [
                                Mode(
                                    scope: "punctuation",
                                    match: #"\:"#
                                ),
                            ]
                        )
                    ),
                    // #ident or #ident:
                    Mode(
                        scope: [
                            1: "punctuation",
                            2: "keyword",
                            3: "punctuation",
                        ],
                        match: [
                            "#+",
                            ident,
                            ":?",
                        ]
                    ),
                ]
            )
        )
    }
}
