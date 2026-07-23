import Foundation

extension LanguageCatalog {
    /// Fish shell. Token-exact port of HighlightKit's checked-in reference
    /// grammar, authored from Fish source/docs at 20569c4.
    public static let fish = LanguageDescriptor(name: "fish") {
        let variable = Mode(
            scope: "variable",
            variants: [
                Mode(match: #"\$\{[A-Za-z_][A-Za-z0-9_]*\}"#),
                Mode(match: #"\$[A-Za-z_][A-Za-z0-9_]*(?:\[[^\]\n]+\])?"#),
            ],
            relevance: 0
        )
        let escape = Mode(
            scope: "char.escape",
            match: #"\\(?:[abefnrtv\\"'$]|x[0-9A-Fa-f]{1,2}|u[0-9A-Fa-f]{1,4}|U[0-9A-Fa-f]{1,8})"#,
            relevance: 0
        )
        let substitution = Mode(scope: "subst", begin: #"\("#, end: #"\)"#, relevance: 0)
        let singleString = Mode(scope: "string", begin: "'", end: "'")
        let doubleString = Mode(
            scope: "string",
            begin: #"""#,
            end: #"""#,
            contains: [escape, variable, substitution]
        )
        substitution.contains = [
            CommonModes.hashCommentMode,
            singleString,
            doubleString,
            variable,
            Mode.selfReference,
        ]
        let keywords = Keywords(
            pattern: #"[A-Za-z_][A-Za-z0-9_-]*"#,
            [
                "keyword": Keywords.Group(words: [
                    "and", "begin", "break", "case", "command", "continue", "else", "end",
                    "exec", "for", "function", "if", "in", "not", "or", "return", "switch",
                    "time", "while",
                ]),
                "literal": Keywords.Group(words: ["true", "false"]),
            ]
        )
        return LanguageDefinition(
            name: "fish",
            aliases: ["fish"],
            disableAutodetect: true,
            root: Mode(
                keywords: keywords,
                contains: [
                    CommonModes.shebang(binary: "fish", relevance: 10),
                    CommonModes.hashCommentMode,
                    singleString,
                    doubleString,
                    variable,
                    substitution,
                    Mode(scope: "meta", match: #"--?[A-Za-z][A-Za-z0-9_-]*"#, relevance: 0),
                    Mode(
                        scope: "operator",
                        match: #"(?:\|&?|&&|\|\||[0-9]*>{1,2}\??|[0-9]*<)"#,
                        relevance: 0
                    ),
                    CommonModes.cNumberMode,
                ]
            )
        )
    }
}
