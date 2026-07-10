import Foundation

extension LanguageCatalog {
    /// PHP. Port of highlight.js `languages/php.js`.
    public static let php = LanguageDescriptor(name: "php") {
        // negative look-ahead tries to avoid matching patterns that are not
        // Perl at all like $ident$, @ident@, etc.
        let notPerlEtc = #"(?![A-Za-z0-9])(?![$])"#
        let identRe = #"[a-zA-Z_\x7f-\xff][a-zA-Z0-9_\x7f-\xff]*"# + notPerlEtc
        // Will not detect camelCase classes
        let pascalCaseClassNameRe =
            #"(\\?[A-Z][a-z0-9_\x7f-\xff]+|\\?[A-Z]+(?=[A-Z][a-z0-9_\x7f-\xff])){1,}"# + notPerlEtc
        let upcaseNameRe = "[A-Z]+" + notPerlEtc

        let variable = Mode(
            scope: "variable",
            match: .re(#"\$+"# + identRe)
        )
        let preprocessor = Mode(
            scope: "meta",
            variants: [
                Mode(begin: #"<\?php"#, relevance: 10), // boost for obvious PHP
                Mode(begin: #"<\?="#),
                // less relevant per PSR-1 which says not to use short-tags
                Mode(begin: #"<\?"#, relevance: 0.1),
                Mode(begin: #"\?>"#), // end php tag
            ]
        )
        let subst = Mode(
            scope: "subst",
            variants: [
                Mode(begin: #"\$\w+"#),
                Mode(begin: #"\{\$"#, end: #"\}"#),
            ]
        )
        let singleQuoted: Mode = {
            let m = CommonModes.aposStringMode
            m.illegal = nil
            return m
        }()
        let doubleQuoted: Mode = {
            let m = CommonModes.quoteStringMode
            m.illegal = nil
            m.contains = (m.contains ?? []) + [subst]
            return m
        }()

        let heredoc = Mode(
            begin: #"<<<[ \t]*(?:(\w+)|"(\w+)")\n"#,
            end: #"[ \t]*(\w+)\b"#,
            contains: [CommonModes.backslashEscape, subst],
            onBegin: { match, response in
                response.data["_beginMatch"] = match[1] ?? match[2] ?? ""
            },
            onEnd: { match, response in
                if response.data["_beginMatch"] != match[1] { response.ignoreMatch() }
            }
        )

        let nowdoc = Mode(
            begin: #"<<<[ \t]*'(\w+)'\n"#,
            end: #"[ \t]*(\w+)\b"#,
            endSameAsBegin: true
        )
        // list of valid whitespaces because non-breaking space might be part of a IDENT_RE
        let whitespace = #"[ \t\n]"#
        let string = Mode(
            scope: "string",
            variants: [
                doubleQuoted,
                singleQuoted,
                heredoc,
                nowdoc,
            ]
        )
        let number = Mode(
            scope: "number",
            variants: [
                // Binary w/ underscore support
                Mode(begin: #"\b0[bB][01]+(?:_[01]+)*\b"#),
                // Octals w/ underscore support
                Mode(begin: #"\b0[oO][0-7]+(?:_[0-7]+)*\b"#),
                // Hex w/ underscore support
                Mode(begin: #"\b0[xX][\da-fA-F]+(?:_[\da-fA-F]+)*\b"#),
                // Decimals w/ underscore support, with optional fragments
                // and scientific exponent (e) suffix.
                Mode(begin: #"(?:\b\d+(?:_\d+)*(\.(?:\d+(?:_\d+)*))?|\B\.\d+)(?:[eE][+-]?\d+)?"#),
            ],
            relevance: 0
        )
        let literals = [
            "false",
            "null",
            "true",
        ]
        let kws = [
            // Magic constants:
            // <https://www.php.net/manual/en/language.constants.predefined.php>
            "__CLASS__",
            "__DIR__",
            "__FILE__",
            "__FUNCTION__",
            "__COMPILER_HALT_OFFSET__",
            "__LINE__",
            "__METHOD__",
            "__NAMESPACE__",
            "__TRAIT__",
            // Function that look like language construct or language
            // construct that look like function: list of keywords that may
            // not require parenthesis
            "die",
            "echo",
            "exit",
            "include",
            "include_once",
            "print",
            "require",
            "require_once",
            // Other keywords:
            // <https://www.php.net/manual/en/reserved.php>
            // <https://www.php.net/manual/en/language.types.type-juggling.php>
            "array",
            "abstract",
            "and",
            "as",
            "binary",
            "bool",
            "boolean",
            "break",
            "callable",
            "case",
            "catch",
            "class",
            "clone",
            "const",
            "continue",
            "declare",
            "default",
            "do",
            "double",
            "else",
            "elseif",
            "empty",
            "enddeclare",
            "endfor",
            "endforeach",
            "endif",
            "endswitch",
            "endwhile",
            "enum",
            "eval",
            "extends",
            "final",
            "finally",
            "float",
            "for",
            "foreach",
            "from",
            "global",
            "goto",
            "if",
            "implements",
            "instanceof",
            "insteadof",
            "int",
            "integer",
            "interface",
            "isset",
            "iterable",
            "list",
            "match|0",
            "mixed",
            "new",
            "never",
            "object",
            "or",
            "private",
            "protected",
            "public",
            "readonly",
            "real",
            "return",
            "string",
            "switch",
            "throw",
            "trait",
            "try",
            "unset",
            "use",
            "var",
            "void",
            "while",
            "xor",
            "yield",
        ]

        let builtIns = [
            // Standard PHP library:
            // <https://www.php.net/manual/en/book.spl.php>
            "Error|0",
            "AppendIterator",
            "ArgumentCountError",
            "ArithmeticError",
            "ArrayIterator",
            "ArrayObject",
            "AssertionError",
            "BadFunctionCallException",
            "BadMethodCallException",
            "CachingIterator",
            "CallbackFilterIterator",
            "CompileError",
            "Countable",
            "DirectoryIterator",
            "DivisionByZeroError",
            "DomainException",
            "EmptyIterator",
            "ErrorException",
            "Exception",
            "FilesystemIterator",
            "FilterIterator",
            "GlobIterator",
            "InfiniteIterator",
            "InvalidArgumentException",
            "IteratorIterator",
            "LengthException",
            "LimitIterator",
            "LogicException",
            "MultipleIterator",
            "NoRewindIterator",
            "OutOfBoundsException",
            "OutOfRangeException",
            "OuterIterator",
            "OverflowException",
            "ParentIterator",
            "ParseError",
            "RangeException",
            "RecursiveArrayIterator",
            "RecursiveCachingIterator",
            "RecursiveCallbackFilterIterator",
            "RecursiveDirectoryIterator",
            "RecursiveFilterIterator",
            "RecursiveIterator",
            "RecursiveIteratorIterator",
            "RecursiveRegexIterator",
            "RecursiveTreeIterator",
            "RegexIterator",
            "RuntimeException",
            "SeekableIterator",
            "SplDoublyLinkedList",
            "SplFileInfo",
            "SplFileObject",
            "SplFixedArray",
            "SplHeap",
            "SplMaxHeap",
            "SplMinHeap",
            "SplObjectStorage",
            "SplObserver",
            "SplPriorityQueue",
            "SplQueue",
            "SplStack",
            "SplSubject",
            "SplTempFileObject",
            "TypeError",
            "UnderflowException",
            "UnexpectedValueException",
            "UnhandledMatchError",
            // Reserved interfaces:
            // <https://www.php.net/manual/en/reserved.interfaces.php>
            "ArrayAccess",
            "BackedEnum",
            "Closure",
            "Fiber",
            "Generator",
            "Iterator",
            "IteratorAggregate",
            "Serializable",
            "Stringable",
            "Throwable",
            "Traversable",
            "UnitEnum",
            "WeakReference",
            "WeakMap",
            // Reserved classes:
            // <https://www.php.net/manual/en/reserved.classes.php>
            "Directory",
            "__PHP_Incomplete_Class",
            "parent",
            "php_user_filter",
            "self",
            "static",
            "stdClass",
        ]

        /// Dual-case keywords: ["then","FILE"] → ["then", "THEN", "FILE", "file"]
        func dualCase(_ items: [String]) -> [String] {
            var result: [String] = []
            for item in items {
                result.append(item)
                if item.lowercased() == item {
                    result.append(item.uppercased())
                } else {
                    result.append(item.lowercased())
                }
            }
            return result
        }

        let keywords = Keywords([
            "keyword": Keywords.Group(words: kws),
            "literal": Keywords.Group(words: dualCase(literals)),
            "built_in": Keywords.Group(words: builtIns),
        ])

        func normalizeKeywords(_ items: [String]) -> [String] {
            items.map { item in
                guard let bar = item.firstIndex(of: "|") else { return item }
                return String(item[..<bar])
            }
        }

        let constructorCall = Mode(variants: [
            Mode(
                scope: [1: "keyword", 4: "title.class"],
                match: [
                    "new",
                    whitespace + "+",
                    // to prevent built ins from being confused as the class
                    // constructor call
                    "(?!" + normalizeKeywords(builtIns).joined(separator: #"\b|"#) + #"\b)"#,
                    pascalCaseClassNameRe,
                ]
            ),
        ])

        let constantReference = identRe + #"\b(?!\()"#

        let leftAndRightSideOfDoubleColon = Mode(variants: [
            Mode(
                scope: [2: "variable.constant"],
                match: [
                    "::" + RegexSource.lookahead(#"(?!class\b)"#),
                    constantReference,
                ]
            ),
            Mode(
                scope: [2: "variable.language"],
                match: [
                    "::",
                    "class",
                ]
            ),
            Mode(
                scope: [1: "title.class", 3: "variable.constant"],
                match: [
                    pascalCaseClassNameRe,
                    "::" + RegexSource.lookahead(#"(?!class\b)"#),
                    constantReference,
                ]
            ),
            Mode(
                scope: [1: "title.class"],
                match: [
                    pascalCaseClassNameRe,
                    "::" + RegexSource.lookahead(#"(?!class\b)"#),
                ]
            ),
            Mode(
                scope: [1: "title.class", 3: "variable.language"],
                match: [
                    pascalCaseClassNameRe,
                    "::",
                    "class",
                ]
            ),
        ])

        let namedArgument = Mode(
            scope: "attr",
            match: .re(identRe + RegexSource.lookahead(":") + RegexSource.lookahead("(?!::)"))
        )
        let paramsMode = Mode(
            begin: #"\("#,
            end: #"\)"#,
            keywords: keywords,
            contains: [
                namedArgument,
                variable,
                leftAndRightSideOfDoubleColon,
                CommonModes.cBlockCommentMode,
                string,
                number,
                constructorCall,
            ],
            relevance: 0
        )
        let functionInvoke = Mode(
            scope: [3: "title.function.invoke"],
            match: [
                #"\b"#,
                // to prevent keywords from being confused as the function title
                #"(?!fn\b|function\b|"#
                    + normalizeKeywords(kws).joined(separator: #"\b|"#)
                    + "|"
                    + normalizeKeywords(builtIns).joined(separator: #"\b|"#)
                    + #"\b)"#,
                identRe,
                whitespace + "*",
                RegexSource.lookahead(#"(?=\()"#),
            ],
            contains: [paramsMode],
            relevance: 0
        )
        paramsMode.contains!.append(functionInvoke)

        let attributeContains: [Mode] = [
            namedArgument,
            leftAndRightSideOfDoubleColon,
            CommonModes.cBlockCommentMode,
            string,
            number,
            constructorCall,
        ]

        let attributes = Mode(
            begin: .re(#"#\[\s*\\?"# + RegexSource.either(pascalCaseClassNameRe, upcaseNameRe)),
            beginScope: "meta",
            end: "]",
            endScope: "meta",
            keywords: Keywords([
                "literal": Keywords.Group(words: literals),
                "keyword": ["new", "array"],
            ]),
            contains: [
                Mode(
                    begin: #"\["#,
                    end: "]",
                    keywords: Keywords([
                        "literal": Keywords.Group(words: literals),
                        "keyword": ["new", "array"],
                    ]),
                    contains: [Mode.selfReference] + attributeContains
                ),
            ] + attributeContains + [
                Mode(
                    scope: "meta",
                    variants: [
                        Mode(match: .re(pascalCaseClassNameRe)),
                        Mode(match: .re(upcaseNameRe)),
                    ]
                ),
            ]
        )

        return LanguageDefinition(
            name: "php",
            root: Mode(
                keywords: keywords,
                contains: [
                    attributes,
                    CommonModes.hashCommentMode,
                    CommonModes.comment("//", "$"),
                    CommonModes.comment(#"/\*"#, #"\*/"#) { mode in
                        mode.contains = [
                            Mode(scope: "doctag", match: "@[A-Za-z]+"),
                        ]
                    },
                    Mode(
                        match: #"__halt_compiler\(\);"#,
                        keywords: "__halt_compiler",
                        starts: Mode(
                            scope: "comment",
                            end: .re(CommonModes.matchNothingRe),
                            contains: [
                                Mode(
                                    scope: "meta",
                                    match: #"\?>"#,
                                    endsParent: true
                                ),
                            ]
                        )
                    ),
                    preprocessor,
                    Mode(
                        scope: "variable.language",
                        match: #"\$this\b"#
                    ),
                    variable,
                    functionInvoke,
                    leftAndRightSideOfDoubleColon,
                    Mode(
                        scope: [1: "keyword", 3: "variable.constant"],
                        match: [
                            "const",
                            #"\s"#,
                            identRe,
                        ]
                    ),
                    constructorCall,
                    Mode(
                        scope: "function",
                        beginKeywords: "fn function",
                        end: "[;{]",
                        illegal: [#"[$%\[]"#],
                        contains: [
                            Mode(beginKeywords: "use"),
                            CommonModes.underscoreTitleMode,
                            Mode(
                                begin: "=>", // No markup, just a relevance booster
                                endsParent: true
                            ),
                            Mode(
                                scope: "params",
                                begin: #"\("#,
                                end: #"\)"#,
                                keywords: keywords,
                                contains: [
                                    Mode.selfReference,
                                    attributes,
                                    variable,
                                    leftAndRightSideOfDoubleColon,
                                    CommonModes.cBlockCommentMode,
                                    string,
                                    number,
                                ],
                                excludeBegin: true,
                                excludeEnd: true
                            ),
                        ],
                        relevance: 0,
                        excludeEnd: true
                    ),
                    Mode(
                        scope: "class",
                        end: #"\{"#,
                        contains: [
                            Mode(beginKeywords: "extends implements"),
                            CommonModes.underscoreTitleMode,
                        ],
                        variants: [
                            Mode(beginKeywords: "enum", illegal: [#"[($"]"#]),
                            Mode(beginKeywords: "class interface trait", illegal: [#"[:($"]"#]),
                        ],
                        relevance: 0,
                        excludeEnd: true
                    ),
                    // both use and namespace still use "old style" rules (vs
                    // multi-match) because the namespace name can include `\`
                    // and we still want each element to be treated as its own
                    // *individual* title
                    Mode(
                        beginKeywords: "namespace",
                        end: ";",
                        illegal: ["[.']"],
                        contains: [
                            {
                                let m = CommonModes.underscoreTitleMode
                                m.scope = "title.class"
                                return m
                            }(),
                        ],
                        relevance: 0
                    ),
                    Mode(
                        beginKeywords: "use",
                        end: ";",
                        contains: [
                            // TODO: title.function vs title.class
                            Mode(scope: "keyword", match: #"\b(as|const|function)\b"#),
                            // TODO: could be title.class or title.function
                            CommonModes.underscoreTitleMode,
                        ],
                        relevance: 0
                    ),
                    string,
                    number,
                ]
            )
        )
    }
}
