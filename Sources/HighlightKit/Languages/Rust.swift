import Foundation

extension LanguageCatalog {
    /// Rust. Port of highlight.js `languages/rust.js`.
    public static let rust = LanguageDescriptor(name: "rust", aliases: ["rs"]) {
        // ============================================
        // Added to support the r# keyword, which is a raw identifier in Rust.
        let rawIdentifier = "(r#)?"
        let underscoreIdentRe = rawIdentifier + CommonModes.underscoreIdentRe
        let identRe = rawIdentifier + CommonModes.identRe
        // ============================================
        let functionInvoke = Mode(
            scope: "title.function.invoke",
            begin: .re(
                #"\b"#
                + #"(?!let|for|while|if|else|match\b)"#
                + identRe
                + RegexSource.lookahead(#"\s*\("#)
            ),
            relevance: 0
        )
        let numberSuffix = "([ui](8|16|32|64|128|size)|f(32|64))?"
        let keywords: [String] = [
            "abstract",
            "as",
            "async",
            "await",
            "become",
            "box",
            "break",
            "const",
            "continue",
            "crate",
            "do",
            "dyn",
            "else",
            "enum",
            "extern",
            "false",
            "final",
            "fn",
            "for",
            "if",
            "impl",
            "in",
            "let",
            "loop",
            "macro",
            "match",
            "mod",
            "move",
            "mut",
            "override",
            "priv",
            "pub",
            "ref",
            "return",
            "self",
            "Self",
            "static",
            "struct",
            "super",
            "trait",
            "true",
            "try",
            "type",
            "typeof",
            "union",
            "unsafe",
            "unsized",
            "use",
            "virtual",
            "where",
            "while",
            "yield",
        ]
        let literals: [String] = [
            "true",
            "false",
            "Some",
            "None",
            "Ok",
            "Err",
        ]
        let builtins: [String] = [
            // functions
            "drop ",
            // traits
            "Copy",
            "Send",
            "Sized",
            "Sync",
            "Drop",
            "Fn",
            "FnMut",
            "FnOnce",
            "ToOwned",
            "Clone",
            "Debug",
            "PartialEq",
            "PartialOrd",
            "Eq",
            "Ord",
            "AsRef",
            "AsMut",
            "Into",
            "From",
            "Default",
            "Iterator",
            "Extend",
            "IntoIterator",
            "DoubleEndedIterator",
            "ExactSizeIterator",
            "SliceConcatExt",
            "ToString",
            // macros
            "assert!",
            "assert_eq!",
            "bitflags!",
            "bytes!",
            "cfg!",
            "col!",
            "concat!",
            "concat_idents!",
            "debug_assert!",
            "debug_assert_eq!",
            "env!",
            "eprintln!",
            "panic!",
            "file!",
            "format!",
            "format_args!",
            "include_bytes!",
            "include_str!",
            "line!",
            "local_data_key!",
            "module_path!",
            "option_env!",
            "print!",
            "println!",
            "select!",
            "stringify!",
            "try!",
            "unimplemented!",
            "unreachable!",
            "vec!",
            "write!",
            "writeln!",
            "macro_rules!",
            "assert_ne!",
            "debug_assert_ne!",
        ]
        let types: [String] = [
            "i8",
            "i16",
            "i32",
            "i64",
            "i128",
            "isize",
            "u8",
            "u16",
            "u32",
            "u64",
            "u128",
            "usize",
            "f32",
            "f64",
            "str",
            "char",
            "bool",
            "Box",
            "Option",
            "Result",
            "String",
            "Vec",
        ]
        // "true" and "false" appear in both KEYWORDS and LITERALS.
        // highlight.js compiles keyword groups in insertion order, so the
        // later `literal` entries win; `Keywords.groups` is an unordered
        // dictionary, so drop the shadowed keyword entries to reproduce
        // the same compiled table deterministically.
        let shadowedByLiterals: Set<String> = ["true", "false"]
        return LanguageDefinition(
            name: "rust",
            aliases: ["rs"],
            root: Mode(
                keywords: Keywords(
                    pattern: CommonModes.identRe + "!?",
                    [
                        "type": Keywords.Group(words: types),
                        "keyword": Keywords.Group(words: keywords.filter { !shadowedByLiterals.contains($0) }),
                        "literal": Keywords.Group(words: literals),
                        "built_in": Keywords.Group(words: builtins),
                    ]
                ),
                illegal: ["</"],
                contains: [
                    CommonModes.cLineCommentMode,
                    CommonModes.comment(#"/\*"#, #"\*/"#) { mode in
                        mode.contains = [Mode.selfReference]
                    },
                    {
                        let m = CommonModes.quoteStringMode
                        m.begin = #"b?""#
                        m.illegal = nil
                        return m
                    }(),
                    Mode(
                        scope: "symbol",
                        // negative lookahead to avoid matching `'`
                        begin: "'[a-zA-Z_][a-zA-Z0-9_]*(?!')"
                    ),
                    Mode(
                        scope: "string",
                        variants: [
                            Mode(begin: #"b?r(#*)"(.|\n)*?"\1(?!#)"#),
                            Mode(
                                begin: "b?'",
                                end: "'",
                                contains: [
                                    Mode(
                                        scope: "char.escape",
                                        match: #"\\('|\w|x\w{2}|u\w{4}|U\w{8})"#
                                    ),
                                ]
                            ),
                        ]
                    ),
                    Mode(
                        scope: "number",
                        variants: [
                            Mode(begin: .re("\\b0b([01_]+)" + numberSuffix)),
                            Mode(begin: .re("\\b0o([0-7_]+)" + numberSuffix)),
                            Mode(begin: .re("\\b0x([A-Fa-f0-9_]+)" + numberSuffix)),
                            Mode(begin: .re("\\b(\\d[\\d_]*(\\.[0-9_]+)?([eE][+-]?[0-9_]+)?)"
                                + numberSuffix)),
                        ],
                        relevance: 0
                    ),
                    Mode(
                        scope: [1: "keyword", 3: "keyword"],
                        begin: [
                            #"\bsafe"#,
                            #"\s+"#,
                            "extern",
                        ]
                    ),
                    Mode(
                        scope: [1: "keyword", 3: "title.function"],
                        begin: [
                            "fn",
                            #"\s+"#,
                            underscoreIdentRe,
                        ]
                    ),
                    Mode(
                        scope: "meta",
                        begin: #"#!?\["#,
                        end: #"\]"#,
                        contains: [
                            Mode(
                                scope: "string",
                                begin: "\"",
                                end: "\"",
                                contains: [CommonModes.backslashEscape]
                            ),
                        ]
                    ),
                    Mode(
                        scope: [1: "keyword", 3: "keyword", 4: "variable"],
                        begin: [
                            "let",
                            #"\s+"#,
                            #"(?:mut\s+)?"#,
                            underscoreIdentRe,
                        ]
                    ),
                    // must come before impl/for rule later
                    Mode(
                        scope: [1: "keyword", 3: "variable", 5: "keyword"],
                        begin: [
                            "for",
                            #"\s+"#,
                            underscoreIdentRe,
                            #"\s+"#,
                            "in",
                        ]
                    ),
                    Mode(
                        scope: [1: "keyword", 3: "title.class"],
                        begin: [
                            "type",
                            #"\s+"#,
                            underscoreIdentRe,
                        ]
                    ),
                    Mode(
                        scope: [1: "keyword", 3: "title.class"],
                        begin: [
                            "(?:trait|enum|struct|union|impl|for)",
                            #"\s+"#,
                            underscoreIdentRe,
                        ]
                    ),
                    Mode(
                        begin: .re(CommonModes.identRe + "::"),
                        keywords: Keywords([
                            "keyword": "Self",
                            "built_in": Keywords.Group(words: builtins),
                            "type": Keywords.Group(words: types),
                        ])
                    ),
                    Mode(scope: "punctuation", begin: "->"),
                    functionInvoke,
                ]
            )
        )
    }
}
