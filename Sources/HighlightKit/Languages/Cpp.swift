import Foundation

extension LanguageCatalog {
    /// C++. Port of highlight.js `languages/cpp.js`.
    public static let cpp = LanguageDescriptor(name: "cpp", aliases: ["cc", "c++", "h++", "hpp", "hh", "hxx", "cxx"]) {
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
        let functionTypeRe = "(?!struct)("
            + decltypeAutoRe + "|"
            + RegexSource.optional(namespaceRe)
            + #"[a-zA-Z_]\w*"# + RegexSource.optional(templateArgumentRe)
            + ")"

        let cppPrimitiveTypes = Mode(
            scope: "type",
            begin: #"\b[a-z\d_]*_t\b"#
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
                // Floating-point literal.
                Mode(begin: .re(
                    "[+-]?(?:" // Leading sign.
                        // Decimal.
                        + "(?:"
                        + #"[0-9](?:'?[0-9])*\.(?:[0-9](?:'?[0-9])*)?"#
                        + #"|\.[0-9](?:'?[0-9])*"#
                        + ")(?:[Ee][+-]?[0-9](?:'?[0-9])*)?"
                        + "|[0-9](?:'?[0-9])*[Ee][+-]?[0-9](?:'?[0-9])*"
                        // Hexadecimal.
                        + "|0[Xx](?:"
                        + #"[0-9A-Fa-f](?:'?[0-9A-Fa-f])*(?:\.(?:[0-9A-Fa-f](?:'?[0-9A-Fa-f])*)?)?"#
                        + #"|\.[0-9A-Fa-f](?:'?[0-9A-Fa-f])*"#
                        + ")[Pp][+-]?[0-9](?:'?[0-9])*"
                        + ")(?:" // Literal suffixes.
                        + "[Ff](?:16|32|64|128)?"
                        + "|(BF|bf)16"
                        + "|[Ll]"
                        + "|" // Literal suffix is optional.
                        + ")"
                )),
                // Integer literal.
                Mode(begin: .re(
                    #"[+-]?\b(?:"# // Leading sign.
                        + "0[Bb][01](?:'?[01])*" // Binary.
                        + "|0[Xx][0-9A-Fa-f](?:'?[0-9A-Fa-f])*" // Hexadecimal.
                        + "|0(?:'?[0-7])*" // Octal or just a lone zero.
                        + "|[1-9](?:'?[0-9])*" // Decimal.
                        + ")(?:" // Literal suffixes.
                        + "[Uu](?:LL?|ll?)"
                        + "|[Uu][Zz]?"
                        + "|(?:LL?|ll?)[Uu]?"
                        + "|[Zz][Uu]"
                        + "|" // Literal suffix is optional.
                        + ")"
                    // Note: there are user-defined literal suffixes too, but
                    // perhaps having the custom suffix not part of the
                    // literal highlight actually makes it stand out more.
                )),
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
                    + "pragma _Pragma ifdef ifndef include"
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

        // https://en.cppreference.com/w/cpp/keyword
        let reservedKeywords = [
            "alignas",
            "alignof",
            "and",
            "and_eq",
            "asm",
            "atomic_cancel",
            "atomic_commit",
            "atomic_noexcept",
            "auto",
            "bitand",
            "bitor",
            "break",
            "case",
            "catch",
            "class",
            "co_await",
            "co_return",
            "co_yield",
            "compl",
            "concept",
            "const_cast|10",
            "consteval",
            "constexpr",
            "constinit",
            "continue",
            "decltype",
            "default",
            "delete",
            "do",
            "dynamic_cast|10",
            "else",
            "enum",
            "explicit",
            "export",
            "extern",
            "false",
            "final",
            "for",
            "friend",
            "goto",
            "if",
            "import",
            "inline",
            "module",
            "mutable",
            "namespace",
            "new",
            "noexcept",
            "not",
            "not_eq",
            "nullptr",
            "operator",
            "or",
            "or_eq",
            "override",
            "private",
            "protected",
            "public",
            "reflexpr",
            "register",
            "reinterpret_cast|10",
            "requires",
            "return",
            "sizeof",
            "static_assert",
            "static_cast|10",
            "struct",
            "switch",
            "synchronized",
            "template",
            "this",
            "thread_local",
            "throw",
            "transaction_safe",
            "transaction_safe_dynamic",
            "true",
            "try",
            "typedef",
            "typeid",
            "typename",
            "union",
            "using",
            "virtual",
            "volatile",
            "while",
            "xor",
            "xor_eq",
        ]

        // https://en.cppreference.com/w/cpp/keyword
        let reservedTypes = [
            "bool",
            "char",
            "char16_t",
            "char32_t",
            "char8_t",
            "double",
            "float",
            "int",
            "long",
            "short",
            "void",
            "wchar_t",
            "unsigned",
            "signed",
            "const",
            "static",
        ]

        let typeHints = [
            "any",
            "auto_ptr",
            "barrier",
            "binary_semaphore",
            "bitset",
            "complex",
            "condition_variable",
            "condition_variable_any",
            "counting_semaphore",
            "deque",
            "false_type",
            "flat_map",
            "flat_set",
            "future",
            "imaginary",
            "initializer_list",
            "istringstream",
            "jthread",
            "latch",
            "lock_guard",
            "multimap",
            "multiset",
            "mutex",
            "optional",
            "ostringstream",
            "packaged_task",
            "pair",
            "promise",
            "priority_queue",
            "queue",
            "recursive_mutex",
            "recursive_timed_mutex",
            "scoped_lock",
            "set",
            "shared_future",
            "shared_lock",
            "shared_mutex",
            "shared_timed_mutex",
            "shared_ptr",
            "stack",
            "string_view",
            "stringstream",
            "timed_mutex",
            "thread",
            "true_type",
            "tuple",
            "unique_lock",
            "unique_ptr",
            "unordered_map",
            "unordered_multimap",
            "unordered_multiset",
            "unordered_set",
            "variant",
            "vector",
            "weak_ptr",
            "wstring",
            "wstring_view",
        ]

        let functionHints = [
            "abort",
            "abs",
            "acos",
            "apply",
            "as_const",
            "asin",
            "atan",
            "atan2",
            "calloc",
            "ceil",
            "cerr",
            "cin",
            "clog",
            "cos",
            "cosh",
            "cout",
            "declval",
            "endl",
            "exchange",
            "exit",
            "exp",
            "fabs",
            "floor",
            "fmod",
            "forward",
            "fprintf",
            "fputs",
            "free",
            "frexp",
            "fscanf",
            "future",
            "invoke",
            "isalnum",
            "isalpha",
            "iscntrl",
            "isdigit",
            "isgraph",
            "islower",
            "isprint",
            "ispunct",
            "isspace",
            "isupper",
            "isxdigit",
            "labs",
            "launder",
            "ldexp",
            "log",
            "log10",
            "make_pair",
            "make_shared",
            "make_shared_for_overwrite",
            "make_tuple",
            "make_unique",
            "malloc",
            "memchr",
            "memcmp",
            "memcpy",
            "memset",
            "modf",
            "move",
            "pow",
            "printf",
            "putchar",
            "puts",
            "realloc",
            "scanf",
            "sin",
            "sinh",
            "snprintf",
            "sprintf",
            "sqrt",
            "sscanf",
            "std",
            "stderr",
            "stdin",
            "stdout",
            "strcat",
            "strchr",
            "strcmp",
            "strcpy",
            "strcspn",
            "strlen",
            "strncat",
            "strncmp",
            "strncpy",
            "strpbrk",
            "strrchr",
            "strspn",
            "strstr",
            "swap",
            "tan",
            "tanh",
            "terminate",
            "to_underlying",
            "tolower",
            "toupper",
            "vfprintf",
            "visit",
            "vprintf",
            "vsprintf",
        ]

        let literals = [
            "NULL",
            "false",
            "nullopt",
            "nullptr",
            "true",
        ]

        // https://en.cppreference.com/w/cpp/keyword
        let builtIn = ["_Pragma"]

        // "true", "false" and "nullptr" appear in both RESERVED_KEYWORDS
        // and LITERALS. highlight.js compiles keyword groups in insertion
        // order, so the later `literal` entries win; `Keywords.groups` is
        // an unordered dictionary, so drop the shadowed keyword entries to
        // reproduce the same compiled table deterministically.
        let shadowedByLiterals: Set<String> = ["true", "false", "nullptr"]
        let cppKeywords = Keywords([
            "type": Keywords.Group(words: reservedTypes),
            "keyword": Keywords.Group(words: reservedKeywords.filter { !shadowedByLiterals.contains($0) }),
            "literal": Keywords.Group(words: literals),
            "built_in": Keywords.Group(words: builtIn),
            "_type_hints": Keywords.Group(words: typeHints),
        ])

        // Keep this list identical to highlight.js's five ordered negative
        // lookaheads. Other reserved words used with call syntax (notably
        // `delete(` and `static_assert(`) deliberately enter
        // `function.dispatch`, whose alias is `built_in`.
        let nonDispatchKeywords = ["decltype", "if", "for", "switch", "while"]
        let functionDispatch = Mode(
            scope: "function.dispatch",
            begin: .re(RegexSource.concat(
                #"\b"#,
                "(?!\(nonDispatchKeywords.joined(separator: "|")))",
                CommonModes.identRe,
                RegexSource.lookahead(#"(<[^<>]+>|)\s*\("#)
            )),
            // Only for relevance, not highlighting.
            keywords: Keywords(["_hint": Keywords.Group(words: functionHints)]),
            relevance: 0
        )

        let expressionContains: [Mode] = [
            functionDispatch,
            preprocessor,
            cppPrimitiveTypes,
            cLineCommentMode,
            cBlockCommentMode,
            numbers,
            strings,
        ]

        // This mode covers expression context where we can't expect a
        // function definition and shouldn't highlight anything that looks
        // like one: `return some()`, `else if()`, `(x*sum(1, 2))`
        let expressionContext = Mode(
            keywords: cppKeywords,
            contains: expressionContains + [
                Mode(
                    begin: #"\("#,
                    end: #"\)"#,
                    keywords: cppKeywords,
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
            scope: "function",
            begin: .re("(" + functionTypeRe + #"[\*&\s]+)+"# + functionTitle),
            end: "[{;=]",
            keywords: cppKeywords,
            illegal: [#"[^\w\s\*&:<>.]"#],
            contains: [
                // to prevent it from being confused as the function title
                Mode(
                    begin: .re(decltypeAutoRe),
                    keywords: cppKeywords,
                    relevance: 0
                ),
                Mode(
                    begin: .re(functionTitle),
                    contains: [titleMode],
                    relevance: 0,
                    returnBegin: true
                ),
                // needed because we do not have look-behind on the below
                // rule to prevent it from grabbing the final : in a :: pair
                Mode(begin: "::", relevance: 0),
                // initializers
                Mode(
                    begin: ":",
                    contains: [
                        strings,
                        numbers,
                    ],
                    endsWithParent: true
                ),
                // allow for multiple declarations, e.g.:
                // extern void f(int), g(char);
                Mode(match: ",", relevance: 0),
                Mode(
                    scope: "params",
                    begin: #"\("#,
                    end: #"\)"#,
                    keywords: cppKeywords,
                    contains: [
                        cLineCommentMode,
                        cBlockCommentMode,
                        strings,
                        numbers,
                        cppPrimitiveTypes,
                        // Count matching parentheses.
                        Mode(
                            begin: #"\("#,
                            end: #"\)"#,
                            keywords: cppKeywords,
                            contains: [
                                Mode.selfReference,
                                cLineCommentMode,
                                cBlockCommentMode,
                                strings,
                                numbers,
                                cppPrimitiveTypes,
                            ],
                            relevance: 0
                        ),
                    ],
                    relevance: 0
                ),
                cppPrimitiveTypes,
                cLineCommentMode,
                cBlockCommentMode,
                preprocessor,
            ],
            excludeEnd: true,
            returnBegin: true
        )

        return LanguageDefinition(
            name: "cpp",
            aliases: ["cc", "c++", "h++", "hpp", "hh", "hxx", "cxx"],
            classNameAliases: ["function.dispatch": "built_in"],
            root: Mode(
                keywords: cppKeywords,
                illegal: ["</"],
                contains: [expressionContext, functionDeclaration, functionDispatch]
                    + expressionContains
                    + [
                        preprocessor,
                        // containers: ie, `vector <int> rooms (9);`
                        Mode(
                            begin: #"\b(deque|list|queue|priority_queue|pair|stack|vector|map|set|bitset|multiset|multimap|unordered_map|unordered_set|unordered_multiset|unordered_multimap|array|tuple|optional|variant|function|flat_map|flat_set)\s*<(?!<)"#,
                            end: ">",
                            keywords: cppKeywords,
                            contains: [
                                Mode.selfReference,
                                cppPrimitiveTypes,
                            ]
                        ),
                        Mode(
                            begin: .re(CommonModes.identRe + "::"),
                            keywords: cppKeywords
                        ),
                        Mode(
                            scope: [1: "keyword", 3: "title.class"],
                            match: [
                                // extra complexity to deal with `enum class`
                                // and `enum struct`
                                #"\b(?:enum(?:\s+(?:class|struct))?|class|struct|union)"#,
                                #"\s+"#,
                                #"\w+"#,
                            ]
                        ),
                    ]
            )
        )
    }
}
