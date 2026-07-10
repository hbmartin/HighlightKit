import Foundation

extension LanguageCatalog {
    /// Prolog. Port of highlight.js `languages/prolog.js`.
    public static let prolog = LanguageDescriptor(name: "prolog") {
        let atom = Mode(
            begin: "[a-z][A-Za-z0-9_]*",
            relevance: 0
        )

        let variable = Mode(
            scope: "symbol",
            variants: [
                Mode(begin: "[A-Z][a-zA-Z0-9_]*"),
                Mode(begin: "_[A-Za-z0-9_]*"),
            ],
            relevance: 0
        )

        let parented = Mode(
            begin: #"\("#,
            end: #"\)"#,
            relevance: 0
        )

        let list = Mode(
            begin: #"\["#,
            end: #"\]"#
        )

        let lineComment = Mode(
            scope: "comment",
            begin: "%",
            end: "$",
            contains: [CommonModes.phrasalWordsMode]
        )

        let backtickString = Mode(
            scope: "string",
            begin: "`",
            end: "`",
            contains: [CommonModes.backslashEscape]
        )

        // 0'a etc.
        let charCode = Mode(
            scope: "string",
            begin: #"0'(\\'|.)"#
        )

        // 0'\s
        let spaceCode = Mode(
            scope: "string",
            begin: #"0'\\s"#
        )

        // relevance booster
        let predOp = Mode(begin: ":-")

        let inner: [Mode] = [
            atom,
            variable,
            parented,
            predOp,
            list,
            lineComment,
            CommonModes.cBlockCommentMode,
            CommonModes.quoteStringMode,
            CommonModes.aposStringMode,
            backtickString,
            charCode,
            spaceCode,
            CommonModes.cNumberMode,
        ]

        parented.contains = inner
        list.contains = inner

        return LanguageDefinition(
            name: "prolog",
            root: Mode(
                contains: inner + [
                    // relevance booster
                    Mode(begin: #"\.$"#),
                ]
            )
        )
    }
}
