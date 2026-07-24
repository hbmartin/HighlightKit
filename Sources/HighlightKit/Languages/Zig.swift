import Foundation

extension LanguageCatalog {
    /// Zig. Port of highlightjs-zig at 6225ff9.
    ///
    /// Upstream quirks are preserved intentionally — the `meme`/`@ass`
    /// built-ins, the `blk` keyword, three overlapping `@identifier` modes,
    /// operator keyword entries the word pattern can never match, and a
    /// regexp mode for a language without regex literals. Fidelity fixtures
    /// assert token-exact output against that pinned commit; do not "fix"
    /// these here without regenerating fixtures from a changed reference.
    public static let zig = LanguageDescriptor(name: "zig") {
        let keywords = Keywords([
            "keyword": Keywords.Group(words: [
                "inline", "while", "for", "extern", "packed", "export", "pub", "noalias",
                "comptime", "volatile", "align", "linksection", "threadlocal", "allowzero",
                "noinline", "callconv", "struct", "enum", "const", "union", "opaque", "asm",
                "unreachable", "break", "return", "continue", "defer", "errdefer", "await",
                "resume", "suspend", "async", "nosuspend", "try", "catch", "if", "else",
                "switch", "orelse", "usingnamespace", "test", "and", "or", "bool", "void",
                "type", "blk",
            ]),
            "literal": Keywords.Group(words: ["true", "false", "null", "undefined"]),
            "built_in": Keywords.Group(words: [
                "std", "meme", "@This", "@Import", "@ass", "i8", "i16", "i32", "i64",
                "i128", "u8", "u16", "u32", "u64", "u128", "f16", "f32", "f64",
                "usize", "isize", "c_short", "c_int", "c_long", "c_longlong", "c_ushort",
                "c_uint", "c_ulong", "c_ulonglong", "c_float", "c_double", "c_void", "mem",
            ]),
            "type": Keywords.Group(words: [
                "anytype", "noreturn", "error", "anyerror", "anyframe", "anyopaque",
            ]),
            "operator": Keywords.Group(words: ["+", "-", "*", "/", "%", "==", "!=", "<", ">", "<=", ">="]),
        ])
        let comments = [CommonModes.cLineCommentMode, CommonModes.cBlockCommentMode]
        let function = Mode(
            scope: "function",
            beginKeywords: "fn",
            end: #"\{"#,
            contains: [
                Mode(scope: "title", begin: #"[a-zA-Z_][a-zA-Z0-9_]*"#, relevance: 0),
                Mode(
                    scope: "params",
                    begin: #"\("#,
                    end: #"\)"#,
                    contains: comments,
                    endsParent: true
                ),
            ],
            excludeEnd: true
        )
        let functionCall = Mode(
            scope: "function-call",
            begin: #"[a-zA-Z_][a-zA-Z0-9_]*\("#,
            end: #"\)"#,
            contains: [Mode(
                scope: "params",
                begin: #"\("#,
                end: #"\)"#,
                contains: comments
            )],
            excludeEnd: true
        )
        let multiline = Mode(
            scope: "multiline",
            begin: #"\\"#,
            end: "$",
            contains: [Mode(begin: #"\\"#, end: "$", relevance: 0)],
            relevance: 0
        )
        return LanguageDefinition(
            name: "zig",
            aliases: ["zig"],
            root: Mode(
                keywords: keywords,
                illegal: [#"/\*"#],
                contains: [
                    Mode(scope: "built_in", begin: #"\bmem\.Copy\b"#),
                    Mode(scope: "meta-event", begin: #"\|[a-zA-Z_]+\|"#),
                    Mode(scope: "comment-todo", begin: #"//\s*TODO:.*$"#),
                    Mode(scope: "comment", begin: #"//[^\n]*"#),
                    Mode(scope: "errorhandling", begin: #"!(?=\w+)"#),
                    Mode(scope: "optional", begin: #"\?(?=[a-zA-Z_])"#),
                    Mode(scope: "operator", begin: #"[-+%/*=<>!]=?|&&|\|\||<<=?|>>=?|\*\*|\+\+|--|->"#),
                    Mode(scope: "property", begin: #"\.\w+"#),
                    CommonModes.cLineCommentMode,
                    CommonModes.quoteStringMode,
                    CommonModes.aposStringMode,
                    CommonModes.cNumberMode,
                    Mode(scope: "string", begin: #"@[a-zA-Z_]\w*"#),
                    Mode(scope: "meta", begin: #"@[a-zA-Z_]\w*"#),
                    Mode(scope: "symbol", begin: #"'[a-zA-Z_][a-zA-Z0-9_]*'"#),
                    Mode(scope: "literal", begin: #"\\[xuU][a-fA-F0-9]+"#),
                    Mode(scope: "number", begin: #"\b0x[0-9a-fA-F]+"#),
                    Mode(scope: "number", begin: #"\b0b[01]+"#),
                    Mode(scope: "number", begin: #"\b0o[0-7]+"#),
                    Mode(scope: "number", begin: #"\b[0-9]+\b"#),
                    CommonModes.regexpMode,
                    function,
                    functionCall,
                    Mode(scope: "macro", begin: #"@[a-zA-Z_][a-zA-Z0-9_]*"#),
                    multiline,
                ]
            )
        )
    }
}
