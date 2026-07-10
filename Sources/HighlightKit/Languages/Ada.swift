import Foundation

extension LanguageCatalog {
    /// Ada. Port of highlight.js `languages/ada.js`.
    public static let ada = LanguageDescriptor(name: "ada") {
        // Regular expression for Ada numeric literals.
        // stolen form the VHDL highlighter

        // Decimal literal:
        let integerRe = #"\d(_|\d)*"#
        let exponentRe = "[eE][-+]?" + integerRe
        let decimalLiteralRe = integerRe + #"(\."# + integerRe + ")?" + "(" + exponentRe + ")?"

        // Based literal:
        let basedIntegerRe = #"\w+"#
        let basedLiteralRe = integerRe + "#" + basedIntegerRe + #"(\."# + basedIntegerRe + ")?" + "#" + "(" + exponentRe + ")?"

        let numberRe = #"\b("# + basedLiteralRe + "|" + decimalLiteralRe + ")"

        // Identifier regex
        let idRegex = "[A-Za-z](_?[A-Za-z0-9.])*"

        // bad chars, only allowed in literals
        let badChars = #"\{\}%#'""#

        // Ada doesn't have block comments, only line comments
        let comments = CommonModes.comment("--", "$")

        // variable declarations of the form
        // Foo : Bar := Baz;
        // where only Bar will be highlighted
        let varDecls = Mode(
            // TODO: These spaces are not required by the Ada syntax
            // however, I have yet to see handwritten Ada code where
            // someone does not put spaces around :
            begin: #"\s+:\s+"#,
            end: #"\s*(:=|;|\)|=>|$)"#,
            illegal: [badChars],
            contains: [
                // workaround to avoid highlighting
                // named loops and declare blocks
                Mode(
                    beginKeywords: "loop for declare others",
                    endsParent: true
                ),
                // properly highlight all modifiers
                Mode(
                    scope: "keyword",
                    beginKeywords: "not null constant access function procedure in out aliased exception"
                ),
                Mode(
                    scope: "type",
                    begin: .re(idRegex),
                    relevance: 0,
                    endsParent: true
                ),
            ]
        )

        let keywords = [
            "abort", "else", "new", "return", "abs", "elsif", "not", "reverse",
            "abstract", "end", "accept", "entry", "select", "access",
            "exception", "of", "separate", "aliased", "exit", "or", "some",
            "all", "others", "subtype", "and", "for", "out", "synchronized",
            "array", "function", "overriding", "at", "tagged", "generic",
            "package", "task", "begin", "goto", "pragma", "terminate", "body",
            "private", "then", "if", "procedure", "type", "case", "in",
            "protected", "constant", "interface", "is", "raise", "use",
            "declare", "range", "delay", "limited", "record", "when", "delta",
            "loop", "rem", "while", "digits", "renames", "with", "do", "mod",
            "requeue", "xor", "parallel",
        ]

        return LanguageDefinition(
            name: "ada",
            caseInsensitive: true,
            root: Mode(
                keywords: Keywords([
                    "keyword": Keywords.Group(words: keywords),
                    "literal": ["True", "False"],
                ]),
                contains: [
                    comments,
                    // strings "foobar"
                    Mode(
                        scope: "string",
                        begin: "\"",
                        end: "\"",
                        contains: [
                            Mode(begin: "\"\"", relevance: 0),
                        ]
                    ),
                    // characters ''
                    Mode(
                        // character literals always contain one char
                        scope: "string",
                        begin: "'.'"
                    ),
                    Mode(
                        // number literals
                        scope: "number",
                        begin: .re(numberRe),
                        relevance: 0
                    ),
                    Mode(
                        // Attributes
                        scope: "symbol",
                        begin: .re("'" + idRegex)
                    ),
                    Mode(
                        // package definition, maybe inside generic
                        scope: "title",
                        begin: #"(\bwith\s+)?(\bprivate\s+)?\bpackage\s+(\bbody\s+)?"#,
                        end: "(is|$)",
                        keywords: "package body",
                        illegal: [badChars],
                        excludeBegin: true,
                        excludeEnd: true
                    ),
                    Mode(
                        // function/procedure declaration/definition
                        // maybe inside generic
                        begin: #"(\b(with|overriding)\s+)?\b(function|procedure)\s+"#,
                        end: #"(\bis|\bwith|\brenames|\)\s*;)"#,
                        keywords: "overriding function procedure with is renames return",
                        // we need to re-match the 'function' keyword, so that
                        // the title mode below matches only exactly once
                        contains: [
                            comments,
                            Mode(
                                // name of the function/procedure
                                scope: "title",
                                begin: #"(\bwith\s+)?\b(function|procedure)\s+"#,
                                end: #"(\(|\s+|$)"#,
                                illegal: [badChars],
                                excludeBegin: true,
                                excludeEnd: true
                            ),
                            // parameter types
                            varDecls,
                            Mode(
                                // return type
                                scope: "type",
                                begin: #"\breturn\s+"#,
                                end: #"(\s+|;|$)"#,
                                keywords: "return",
                                illegal: [badChars],
                                excludeBegin: true,
                                excludeEnd: true,
                                // we are done with functions
                                endsParent: true
                            ),
                        ],
                        returnBegin: true
                    ),
                    Mode(
                        // new type declarations
                        // maybe inside generic
                        scope: "type",
                        begin: #"\b(sub)?type\s+"#,
                        end: #"\s+"#,
                        keywords: "type",
                        illegal: [badChars],
                        excludeBegin: true
                    ),

                    // see comment above the definition
                    varDecls,
                ]
            )
        )
    }
}
