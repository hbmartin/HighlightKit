import Foundation

extension LanguageCatalog {
    /// Delphi. Port of highlight.js `languages/delphi.js`.
    public static let delphi = LanguageDescriptor(name: "delphi", aliases: ["dpr", "dfm", "pas", "pascal"]) {
        let keywords: [String] = [
            "exports", "register", "file", "shl", "array", "record", "property", "for",
            "mod", "while", "set", "ally", "label", "uses", "raise", "not", "stored",
            "class", "safecall", "var", "interface", "or", "private", "static", "exit",
            "index", "inherited", "to", "else", "stdcall", "override", "shr", "asm",
            "far", "resourcestring", "finalization", "packed", "virtual", "out", "and",
            "protected", "library", "do", "xorwrite", "goto", "near", "function", "end",
            "div", "overload", "object", "unit", "begin", "string", "on", "inline",
            "repeat", "until", "destructor", "write", "message", "program", "with",
            "read", "initialization", "except", "default", "nil", "if", "case", "cdecl",
            "in", "downto", "threadvar", "of", "try", "pascal", "const", "external",
            "constructor", "type", "public", "then", "implementation", "finally",
            "published", "procedure", "absolute", "reintroduce", "operator", "as", "is",
            "abstract", "alias", "assembler", "bitpacked", "break", "continue", "cppdecl",
            "cvar", "enumerator", "experimental", "platform", "deprecated",
            "unimplemented", "dynamic", "export", "far16", "forward", "generic", "helper",
            "implements", "interrupt", "iochecks", "local", "name", "nodefault",
            "noreturn", "nostackframe", "oldfpccall", "otherwise", "saveregisters",
            "softfloat", "specialize", "strict", "unaligned", "varargs",
        ]
        let commentModes: [Mode] = [
            CommonModes.cLineCommentMode,
            CommonModes.comment(#"\{"#, #"\}"#) { $0.relevance = 0 },
            CommonModes.comment(#"\(\*"#, #"\*\)"#) { $0.relevance = 10 },
        ]
        let directive = Mode(
            scope: "meta",
            variants: [
                Mode(begin: #"\{\$"#, end: #"\}"#),
                Mode(begin: #"\(\*\$"#, end: #"\*\)"#),
            ]
        )
        let string = Mode(
            scope: "string",
            begin: "'",
            end: "'",
            contains: [Mode(begin: "''")]
        )
        let number = Mode(
            scope: "number",
            // Source: https://www.freepascal.org/docs-html/ref/refse6.html
            variants: [
                // Regular numbers, e.g., 123, 123.456.
                Mode(match: #"\b\d[\d_]*(\.\d[\d_]*)?"#),
                // Hexadecimal notation, e.g., $7F.
                Mode(match: #"\$[\dA-Fa-f_]+"#),
                // Hexadecimal literal with no digits
                Mode(match: #"\$"#, relevance: 0),
                // Octal notation, e.g., &42.
                Mode(match: "&[0-7][0-7_]*"),
                // Binary notation, e.g., %1010.
                Mode(match: "%[01_]+"),
                // Binary literal with no digits
                Mode(match: "%", relevance: 0),
            ],
            relevance: 0
        )
        let charString = Mode(
            scope: "string",
            variants: [
                Mode(match: #"#\d[\d_]*"#),
                Mode(match: #"#\$[\dA-Fa-f][\dA-Fa-f_]*"#),
                Mode(match: "#&[0-7][0-7_]*"),
                Mode(match: "#%[01][01_]*"),
            ]
        )
        let klass = Mode(
            begin: .re(CommonModes.identRe + #"\s*=\s*class\s*\("#),
            contains: [CommonModes.titleMode],
            returnBegin: true
        )
        let function = Mode(
            scope: "function",
            beginKeywords: "function constructor destructor procedure",
            end: "[:;]",
            keywords: "function constructor|10 destructor|10 procedure|10",
            contains: [
                CommonModes.titleMode,
                Mode(
                    scope: "params",
                    begin: #"\("#,
                    end: #"\)"#,
                    keywords: Keywords(keyword: Keywords.Group(words: keywords)),
                    contains: [
                        string,
                        charString,
                        directive,
                    ] + commentModes
                ),
                directive,
            ] + commentModes
        )

        return LanguageDefinition(
            name: "delphi",
            aliases: ["dpr", "dfm", "pas", "pascal"],
            caseInsensitive: true,
            root: Mode(
                keywords: Keywords(keyword: Keywords.Group(words: keywords)),
                illegal: [#""|\$[G-Zg-z]|\/\*|<\/|\|"#],
                contains: [
                    string,
                    charString,
                    number,
                    klass,
                    function,
                    directive,
                ] + commentModes
            )
        )
    }
}
