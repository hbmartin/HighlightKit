import Foundation

extension LanguageCatalog {
    /// C. Port of highlight.js `languages/c.js`.
    public static let c = LanguageDescriptor(name: "c", aliases: ["h"]) {
        // added for historic reasons because `hljs.C_LINE_COMMENT_MODE` does
        // not include such support nor can we be sure all the grammars
        // depending on it would desire this behavior
        let cLineCommentMode = CommonModes.comment("//", "$") { mode in
            mode.contains = [Mode(begin: #"\\\n"#)]
        }
        let cBlockCommentMode = CommonModes.cBlockCommentMode
        let decltypeAutoRe = #"decltype\(auto\)"#
        let namespaceRe = #"[a-zA-Z_]\w*::"#
        let templateArgumentRe = "<[^<>]+>"
        let functionTypeRe = "("
            + decltypeAutoRe + "|"
            + RegexSource.optional(namespaceRe)
            + #"[a-zA-Z_]\w*"# + RegexSource.optional(templateArgumentRe)
            + ")"

        let types = Mode(
            scope: "type",
            variants: [
                Mode(begin: #"\b[a-z\d_]*_t\b"#),
                Mode(match: #"\batomic_[a-z]{3,6}\b"#),
            ]
        )

        // https://en.cppreference.com/w/cpp/language/escape
        // backslash, \x, \xFF, \u2837, \u00323747, \374
        let characterEscapes = #"\\(x[0-9A-Fa-f]{2}|u[0-9A-Fa-f]{4,8}|[0-7]{3}|\S)"#
        let strings = Mode(
            scope: "string",
            variants: [
                Mode(
                    begin: "(u8?|U|L)?\"",
                    end: "\"",
                    illegal: [#"\n"#],
                    contains: [CommonModes.backslashEscape]
                ),
                Mode(
                    begin: .re("(u8?|U|L)?'(" + characterEscapes + "|.)"),
                    end: "'",
                    illegal: ["."]
                ),
                Mode(
                    begin: #"(?:u8?|U|L)?R"([^()\\ ]{0,16})\("#,
                    end: #"\)([^()\\ ]{0,16})""#,
                    endSameAsBegin: true
                ),
            ]
        )

        let numbers = Mode(
            scope: "number",
            variants: [
                Mode(match: #"\b(0b[01']+)"#),
                Mode(match: #"(-?)\b([\d']+(\.[\d']*)?|\.[\d']+)((ll|LL|l|L)(u|U)?|(u|U)(ll|LL|l|L)?|f|F|b|B)"#),
                Mode(match: #"(-?)\b(0[xX][a-fA-F0-9]+(?:'[a-fA-F0-9]+)*(?:\.[a-fA-F0-9]*(?:'[a-fA-F0-9]*)*)?(?:[pP][-+]?[0-9]+)?(l|L)?(u|U)?)"#),
                Mode(match: #"(-?)\b\d+(?:'\d+)*(?:\.\d*(?:'\d*)*)?(?:[eE][-+]?\d+)?"#),
            ],
            relevance: 0
        )

        let preprocessor = Mode(
            scope: "meta",
            begin: #"#\s*[a-z]+\b"#,
            end: "$",
            keywords: Keywords(
                keyword: Keywords.Group(stringLiteral:
                    "if else elif endif define undef warning error line "
                    + "pragma _Pragma ifdef ifndef elifdef elifndef include"
                )
            ),
            contains: [
                Mode(begin: #"\\\n"#, relevance: 0),
                strings.copied { $0.scope = "string" },
                Mode(scope: "string", begin: "<.*?>"),
                cLineCommentMode,
                cBlockCommentMode,
            ]
        )

        let titleMode = Mode(
            scope: "title",
            begin: .re(RegexSource.optional(namespaceRe) + CommonModes.identRe),
            relevance: 0
        )

        let functionTitle = RegexSource.optional(namespaceRe) + CommonModes.identRe + #"\s*\("#

        let cKeywords = [
            "asm",
            "auto",
            "break",
            "case",
            "continue",
            "default",
            "do",
            "else",
            "enum",
            "extern",
            "for",
            "fortran",
            "goto",
            "if",
            "inline",
            "register",
            "restrict",
            "return",
            "sizeof",
            "typeof",
            "typeof_unqual",
            "struct",
            "switch",
            "typedef",
            "union",
            "volatile",
            "while",
            "_Alignas",
            "_Alignof",
            "_Atomic",
            "_Generic",
            "_Noreturn",
            "_Static_assert",
            "_Thread_local",
            // aliases
            "alignas",
            "alignof",
            "noreturn",
            "static_assert",
            "thread_local",
            // not a C keyword but is, for all intents and purposes, treated
            // exactly like one.
            "_Pragma",
        ]

        let cTypes = [
            "float",
            "double",
            "signed",
            "unsigned",
            "int",
            "short",
            "long",
            "char",
            "void",
            "_Bool",
            "_BitInt",
            "_Complex",
            "_Imaginary",
            "_Decimal32",
            "_Decimal64",
            "_Decimal96",
            "_Decimal128",
            "_Decimal64x",
            "_Decimal128x",
            "_Float16",
            "_Float32",
            "_Float64",
            "_Float128",
            "_Float32x",
            "_Float64x",
            "_Float128x",
            // modifiers
            "const",
            "static",
            "constexpr",
            // aliases
            "complex",
            "bool",
            "imaginary",
        ]

        let keywords = Keywords([
            "keyword": Keywords.Group(words: cKeywords),
            "type": Keywords.Group(words: cTypes),
            "literal": "true false NULL",
            // TODO: apply hinting work similar to what was done in cpp.js
            "built_in": Keywords.Group(stringLiteral:
                "std string wstring cin cout cerr clog stdin stdout stderr stringstream istringstream ostringstream "
                + "auto_ptr deque list queue stack vector map set pair bitset multiset multimap unordered_set "
                + "unordered_map unordered_multiset unordered_multimap priority_queue make_pair array shared_ptr abort terminate abs acos "
                + "asin atan2 atan calloc ceil cosh cos exit exp fabs floor fmod fprintf fputs free frexp "
                + "fscanf future isalnum isalpha iscntrl isdigit isgraph islower isprint ispunct isspace isupper "
                + "isxdigit tolower toupper labs ldexp log10 log malloc realloc memchr memcmp memcpy memset modf pow "
                + "printf putchar puts scanf sinh sin snprintf sprintf sqrt sscanf strcat strchr strcmp "
                + "strcpy strcspn strlen strncat strncmp strncpy strpbrk strrchr strspn strstr tanh tan "
                + "vfprintf vprintf vsprintf endl initializer_list unique_ptr"
            ),
        ])

        let expressionContains: [Mode] = [
            preprocessor,
            types,
            cLineCommentMode,
            cBlockCommentMode,
            numbers,
            strings,
        ]

        // This mode covers expression context where we can't expect a
        // function definition and shouldn't highlight anything that looks
        // like one: `return some()`, `else if()`, `(x*sum(1, 2))`
        let expressionContext = Mode(
            keywords: keywords,
            contains: expressionContains + [
                Mode(
                    begin: #"\("#,
                    end: #"\)"#,
                    keywords: keywords,
                    contains: expressionContains + [Mode.selfReference],
                    relevance: 0
                ),
            ],
            variants: [
                Mode(begin: "=", end: ";"),
                Mode(begin: #"\("#, end: #"\)"#),
                Mode(beginKeywords: "new throw return else", end: ";"),
            ],
            relevance: 0
        )

        let functionDeclaration = Mode(
            begin: .re("(" + functionTypeRe + #"[\*&\s]+)+"# + functionTitle),
            end: "[{;=]",
            keywords: keywords,
            illegal: [#"[^\w\s\*&:<>.]"#],
            contains: [
                // to prevent it from being confused as the function title
                Mode(
                    begin: .re(decltypeAutoRe),
                    keywords: keywords,
                    relevance: 0
                ),
                Mode(
                    begin: .re(functionTitle),
                    contains: [titleMode.copied { $0.scope = "title.function" }],
                    relevance: 0,
                    returnBegin: true
                ),
                // allow for multiple declarations, e.g.:
                // extern void f(int), g(char);
                Mode(match: ",", relevance: 0),
                Mode(
                    scope: "params",
                    begin: #"\("#,
                    end: #"\)"#,
                    keywords: keywords,
                    contains: [
                        cLineCommentMode,
                        cBlockCommentMode,
                        strings,
                        numbers,
                        types,
                        // Count matching parentheses.
                        Mode(
                            begin: #"\("#,
                            end: #"\)"#,
                            keywords: keywords,
                            contains: [
                                Mode.selfReference,
                                cLineCommentMode,
                                cBlockCommentMode,
                                strings,
                                numbers,
                                types,
                            ],
                            relevance: 0
                        ),
                    ],
                    relevance: 0
                ),
                types,
                cLineCommentMode,
                cBlockCommentMode,
                preprocessor,
            ],
            excludeEnd: true,
            returnBegin: true
        )

        return LanguageDefinition(
            name: "c",
            aliases: ["h"],
            // Until differentiations are added between `c` and `cpp`, `c`
            // will not be auto-detected to avoid auto-detect conflicts
            // between C and C++
            disableAutodetect: true,
            root: Mode(
                keywords: keywords,
                illegal: ["</"],
                contains: [expressionContext, functionDeclaration]
                    + expressionContains
                    + [
                        preprocessor,
                        Mode(
                            begin: .re(CommonModes.identRe + "::"),
                            keywords: keywords
                        ),
                        Mode(
                            scope: "class",
                            beginKeywords: "enum class struct union",
                            end: "[{;:<>=]",
                            contains: [
                                Mode(beginKeywords: "final class struct"),
                                CommonModes.titleMode,
                            ]
                        ),
                    ]
            )
        )
    }
}
