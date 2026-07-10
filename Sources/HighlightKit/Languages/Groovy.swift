import Foundation

extension LanguageCatalog {
    /// Groovy. Port of highlight.js `languages/groovy.js`.
    public static let groovy = LanguageDescriptor(name: "groovy") {
        let identRe = "[A-Za-z0-9_$]+"

        let comment = Mode(
            variants: [
                CommonModes.cLineCommentMode,
                CommonModes.cBlockCommentMode,
                CommonModes.comment(#"/\*\*"#, #"\*/"#) { mode in
                    mode.relevance = 0
                    mode.contains = [
                        // eat up @'s in emails to prevent them to be
                        // recognized as doctags
                        Mode(begin: #"\w+@"#, relevance: 0),
                        Mode(scope: "doctag", begin: "@[A-Za-z]+"),
                    ]
                },
            ]
        )
        let regexp = Mode(
            scope: "regexp",
            begin: #"~?/[^/\n]+/"#,
            contains: [CommonModes.backslashEscape]
        )
        // Pinned highlight.js intentionally uses only its shared binary and
        // C-number modes here, not Java's newer underscore-aware grammar.
        let number = Mode(
            variants: [
                CommonModes.binaryNumberMode,
                CommonModes.cNumberMode,
            ]
        )
        let string = Mode(
            scope: "string",
            variants: [
                Mode(begin: "\"\"\"", end: "\"\"\""),
                Mode(begin: "'''", end: "'''"),
                Mode(begin: #"\$/"#, end: #"/\$"#, relevance: 10),
                CommonModes.aposStringMode,
                CommonModes.quoteStringMode,
            ]
        )

        let classDefinition = Mode(
            scope: [1: "keyword", 3: "title.class"],
            match: [
                "(class|interface|trait|enum|record|extends|implements)",
                #"\s+"#,
                CommonModes.underscoreIdentRe,
            ]
        )
        let types: Keywords.Group = Keywords.Group(words: [
            "byte",
            "short",
            "char",
            "int",
            "long",
            "boolean",
            "float",
            "double",
            "void",
        ])
        let keywords: Keywords.Group = Keywords.Group(words: [
            // groovy specific keywords
            "def",
            "as",
            "in",
            "assert",
            "trait",
            // common keywords with Java
            "abstract",
            "static",
            "volatile",
            "transient",
            "public",
            "private",
            "protected",
            "synchronized",
            "final",
            "class",
            "interface",
            "enum",
            "if",
            "else",
            "for",
            "while",
            "switch",
            "case",
            "break",
            "default",
            "continue",
            "throw",
            "throws",
            "try",
            "catch",
            "finally",
            "implements",
            "extends",
            "new",
            "import",
            "package",
            "return",
            "instanceof",
            "var",
        ])

        return LanguageDefinition(
            name: "groovy",
            root: Mode(
                keywords: Keywords([
                    "variable.language": "this super",
                    "literal": "true false null",
                    "type": types,
                    "keyword": keywords,
                ]),
                illegal: [#"#|<\/"#],
                contains: [
                    CommonModes.shebang(binary: "groovy", relevance: 10),
                    comment,
                    string,
                    regexp,
                    number,
                    classDefinition,
                    Mode(scope: "meta", begin: "@[A-Za-z]+", relevance: 0),
                    // highlight map keys and named parameters as attrs
                    Mode(scope: "attr", begin: .re(identRe + "[ \t]*:"), relevance: 0),
                    // catch middle element of the ternary operator
                    // to avoid highlight it as a label, named parameter,
                    // or map key
                    Mode(
                        begin: #"\?"#,
                        end: ":",
                        contains: [
                            comment,
                            string,
                            regexp,
                            number,
                            Mode.selfReference,
                        ],
                        relevance: 0
                    ),
                    // highlight labeled statements
                    Mode(
                        scope: "symbol",
                        begin: .re("^[ \t]*" + RegexSource.lookahead(identRe + ":")),
                        end: .re(identRe + ":"),
                        relevance: 0,
                        excludeBegin: true
                    ),
                ]
            )
        )
    }
}
