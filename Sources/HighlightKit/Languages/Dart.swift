import Foundation

extension LanguageCatalog {
    /// Dart. Port of highlight.js `languages/dart.js`.
    public static let dart = LanguageDescriptor(name: "dart") {
        let subst = Mode(
            scope: "subst",
            variants: [
                Mode(begin: #"\$[A-Za-z0-9_]+"#),
            ]
        )

        let bracedSubst = Mode(
            scope: "subst",
            keywords: "true false null this is new super",
            variants: [
                Mode(begin: #"\$\{"#, end: #"\}"#),
            ]
            // contains is defined later (cyclic)
        )

        let number = Mode(
            scope: "number",
            variants: [
                Mode(match: #"\b[0-9][0-9_]*(\.[0-9][0-9_]*)?([eE][+-]?[0-9][0-9_]*)?\b"#),
                Mode(match: #"\b0[xX][0-9A-Fa-f][0-9A-Fa-f_]*\b"#),
            ],
            relevance: 0
        )

        let string = Mode(
            scope: "string",
            variants: [
                Mode(begin: "r'''", end: "'''"),
                Mode(begin: "r\"\"\"", end: "\"\"\""),
                Mode(begin: "r'", end: "'", illegal: [#"\n"#]),
                Mode(begin: "r\"", end: "\"", illegal: [#"\n"#]),
                Mode(
                    begin: "'''",
                    end: "'''",
                    contains: [CommonModes.backslashEscape, subst, bracedSubst]
                ),
                Mode(
                    begin: "\"\"\"",
                    end: "\"\"\"",
                    contains: [CommonModes.backslashEscape, subst, bracedSubst]
                ),
                Mode(
                    begin: "'",
                    end: "'",
                    illegal: [#"\n"#],
                    contains: [CommonModes.backslashEscape, subst, bracedSubst]
                ),
                Mode(
                    begin: "\"",
                    end: "\"",
                    illegal: [#"\n"#],
                    contains: [CommonModes.backslashEscape, subst, bracedSubst]
                ),
            ]
        )
        bracedSubst.contains = [
            number,
            string,
        ]

        let builtInTypes = [
            // dart:core
            "Comparable",
            "DateTime",
            "Duration",
            "Function",
            "Iterable",
            "Iterator",
            "List",
            "Map",
            "Match",
            "Object",
            "Pattern",
            "RegExp",
            "Set",
            "Stopwatch",
            "String",
            "StringBuffer",
            "StringSink",
            "Symbol",
            "Type",
            "Uri",
            "bool",
            "double",
            "int",
            "num",
            // dart:html
            "Element",
            "ElementList",
        ]
        let nullableBuiltInTypes = builtInTypes.map { "\($0)?" }

        // Note: "Function" and "dynamic" are omitted here (unlike the JS
        // source's BASIC_KEYWORDS) — they also appear in the built_in group
        // below, which wins in highlight.js' insertion-ordered keyword
        // compilation.
        let basicKeywords = [
            "abstract",
            "as",
            "assert",
            "async",
            "await",
            "base",
            "break",
            "case",
            "catch",
            "class",
            "const",
            "continue",
            "covariant",
            "default",
            "deferred",
            "do",
            "else",
            "enum",
            "export",
            "extends",
            "extension",
            "external",
            "factory",
            "false",
            "final",
            "finally",
            "for",
            "get",
            "hide",
            "if",
            "implements",
            "import",
            "in",
            "interface",
            "is",
            "late",
            "library",
            "mixin",
            "new",
            "null",
            "on",
            "operator",
            "part",
            "required",
            "rethrow",
            "return",
            "sealed",
            "set",
            "show",
            "static",
            "super",
            "switch",
            "sync",
            "this",
            "throw",
            "true",
            "try",
            "typedef",
            "var",
            "void",
            "when",
            "while",
            "with",
            "yield",
        ]

        let keywords = Keywords(
            pattern: #"[A-Za-z][A-Za-z0-9_]*\??"#,
            [
                "keyword": Keywords.Group(words: basicKeywords),
                "built_in": Keywords.Group(
                    words: builtInTypes
                        + nullableBuiltInTypes
                        + [
                            // dart:core
                            "Never",
                            "Null",
                            "dynamic",
                            "print",
                            // dart:html
                            "document",
                            "querySelector",
                            "querySelectorAll",
                            "window",
                        ]
                ),
            ]
        )

        return LanguageDefinition(
            name: "dart",
            root: Mode(
                keywords: keywords,
                contains: [
                    string,
                    CommonModes.comment(#"/\*\*(?!/)"#, #"\*/"#) { mode in
                        mode.subLanguage = ["markdown"]
                        mode.relevance = 0
                    },
                    CommonModes.comment("/{3,} ?", "$") { mode in
                        mode.contains = [
                            Mode(
                                begin: ".",
                                end: "$",
                                subLanguage: ["markdown"],
                                relevance: 0
                            ),
                        ]
                    },
                    CommonModes.cLineCommentMode,
                    CommonModes.cBlockCommentMode,
                    Mode(
                        scope: "class",
                        beginKeywords: "class interface",
                        end: #"\{"#,
                        contains: [
                            Mode(beginKeywords: "extends implements"),
                            CommonModes.underscoreTitleMode,
                        ],
                        excludeEnd: true
                    ),
                    number,
                    Mode(scope: "meta", begin: "@[A-Za-z]+"),
                    Mode(begin: "=>"), // No markup, just a relevance booster
                ]
            )
        )
    }
}
