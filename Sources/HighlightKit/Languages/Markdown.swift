import Foundation

extension LanguageCatalog {
    /// Markdown. Port of highlight.js `languages/markdown.js`.
    public static let markdown = LanguageDescriptor(name: "markdown", aliases: ["md", "mkdown", "mkd"]) {
        let inlineHtml = Mode(
            begin: #"<\/?[A-Za-z_]"#,
            end: ">",
            subLanguage: ["xml"],
            relevance: 0
        )
        let horizontalRule = Mode(
            begin: #"^[-\*]{3,}"#,
            end: "$"
        )
        let code = Mode(
            scope: "code",
            variants: [
                // TODO: fix to allow these to work with sublanguage also
                Mode(begin: #"(`{3,})[^`](.|\n)*?\1`*[ ]*"#),
                Mode(begin: #"(~{3,})[^~](.|\n)*?\1~*[ ]*"#),
                // needed to allow markdown as a sublanguage to work
                Mode(begin: "```", end: "```+[ ]*$"),
                Mode(begin: "~~~", end: "~~~+[ ]*$"),
                Mode(begin: "`.+?`"),
                Mode(
                    begin: #"(?=^( {4}|\t))"#,
                    // use contains to gobble up multiple lines to allow the
                    // block to be whatever size but only have a single
                    // open/close tag vs one per line
                    contains: [
                        Mode(begin: #"^( {4}|\t)"#, end: #"(\n)$"#),
                    ],
                    relevance: 0
                ),
            ]
        )
        let list = Mode(
            scope: "bullet",
            begin: #"^[ \t]*([*+-]|(\d+\.))(?=\s+)"#,
            end: #"\s+"#,
            excludeEnd: true
        )
        let linkReference = Mode(
            begin: #"^\[[^\n]+\]:"#,
            contains: [
                Mode(
                    scope: "symbol",
                    begin: #"\["#,
                    end: #"\]"#,
                    excludeBegin: true,
                    excludeEnd: true
                ),
                Mode(
                    scope: "link",
                    begin: #":\s*"#,
                    end: "$",
                    excludeBegin: true
                ),
            ],
            returnBegin: true
        )
        let urlScheme = #"[A-Za-z][A-Za-z0-9+.-]*"#
        let link = Mode(
            contains: [
                // empty strings for alt or link text
                Mode(match: #"\[(?=\])"#),
                Mode(
                    scope: "string",
                    begin: #"\["#,
                    end: #"\]"#,
                    relevance: 0,
                    excludeBegin: true,
                    returnEnd: true
                ),
                Mode(
                    scope: "link",
                    begin: #"\]\("#,
                    end: #"\)"#,
                    relevance: 0,
                    excludeBegin: true,
                    excludeEnd: true
                ),
                Mode(
                    scope: "symbol",
                    begin: #"\]\["#,
                    end: #"\]"#,
                    relevance: 0,
                    excludeBegin: true,
                    excludeEnd: true
                ),
            ],
            variants: [
                // too much like nested array access in so many languages
                // to have any real relevance
                Mode(begin: #"\[.+?\]\[.*?\]"#, relevance: 0),
                // popular internet URLs
                Mode(
                    begin: #"\[.+?\]\(((data|javascript|mailto):|(?:http|ftp)s?://).*?\)"#,
                    relevance: 2
                ),
                Mode(
                    begin: .re(RegexSource.concat(#"\[.+?\]\("#, urlScheme, #"://.*?\)"#)),
                    relevance: 2
                ),
                // relative urls
                Mode(begin: #"\[.+?\]\([./?&#].*?\)"#, relevance: 1),
                // whatever else, lower relevance (might not be a link at all)
                Mode(begin: #"\[.*?\]\(.*?\)"#, relevance: 0),
            ],
            returnBegin: true
        )
        let bold = Mode(
            scope: "strong",
            contains: [], // defined later
            variants: [
                Mode(begin: #"_{2}(?!\s)"#, end: #"_{2}"#),
                Mode(begin: #"\*{2}(?!\s)"#, end: #"\*{2}"#),
            ]
        )
        let italic = Mode(
            scope: "emphasis",
            contains: [], // defined later
            variants: [
                Mode(begin: #"\*(?![*\s])"#, end: #"\*"#),
                Mode(begin: #"_(?![_\s])"#, end: "_", relevance: 0),
            ]
        )

        // 3 level deep nesting is not allowed because it would create
        // confusion in cases like `***testing***` because where we don't
        // know if the last `***` is starting a new bold/italic or finishing
        // the last one
        let boldWithoutItalic = bold.copied { $0.contains = [] }
        let italicWithoutBold = italic.copied { $0.contains = [] }
        bold.contains!.append(italicWithoutBold)
        italic.contains!.append(boldWithoutItalic)

        var containable: [Mode] = [
            inlineHtml,
            link,
        ]

        for m in [bold, italic, boldWithoutItalic, italicWithoutBold] {
            m.contains = (m.contains ?? []) + containable
        }

        containable += [bold, italic]

        let header = Mode(
            scope: "section",
            variants: [
                Mode(begin: "^#{1,6}", end: "$", contains: containable),
                Mode(
                    begin: #"(?=^.+?\n[=-]{2,}$)"#,
                    contains: [
                        Mode(begin: "^[=-]*$"),
                        Mode(begin: "^", end: #"\n"#, contains: containable),
                    ]
                ),
            ]
        )

        let blockquote = Mode(
            scope: "quote",
            begin: #"^>\s+"#,
            end: "$",
            contains: containable
        )

        let entity = Mode(
            // https://spec.commonmark.org/0.31.2/#entity-references
            scope: "literal",
            match: #"&([a-zA-Z0-9]+|#[0-9]{1,7}|#[Xx][0-9a-fA-F]{1,6});"#
        )

        return LanguageDefinition(
            name: "markdown",
            aliases: ["md", "mkdown", "mkd"],
            root: Mode(
                contains: [
                    header,
                    inlineHtml,
                    list,
                    bold,
                    italic,
                    blockquote,
                    code,
                    horizontalRule,
                    link,
                    linkReference,
                    entity,
                ]
            )
        )
    }
}
