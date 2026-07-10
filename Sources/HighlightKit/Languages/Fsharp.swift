import Foundation

extension LanguageCatalog {
    /// F#. Port of highlight.js `languages/fsharp.js`.
    public static let fsharp = LanguageDescriptor(name: "fsharp", aliases: ["fs", "f#"]) {
        let keywords = [
            "abstract",
            "and",
            "as",
            "assert",
            "base",
            "begin",
            "class",
            "default",
            "delegate",
            "do",
            "done",
            "downcast",
            "downto",
            "elif",
            "else",
            "end",
            "exception",
            "extern",
            // "false", // literal
            "finally",
            "fixed",
            "for",
            "fun",
            "function",
            "global",
            "if",
            "in",
            "inherit",
            "inline",
            "interface",
            "internal",
            "lazy",
            "let",
            "match",
            "member",
            "module",
            "mutable",
            "namespace",
            "new",
            // "not", // built_in
            // "null", // literal
            "of",
            "open",
            "or",
            "override",
            "private",
            "public",
            "rec",
            "return",
            "static",
            "struct",
            "then",
            "to",
            // "true", // literal
            "try",
            "type",
            "upcast",
            "use",
            "val",
            "void",
            "when",
            "while",
            "with",
            "yield",
        ]

        let bangKeywordMode = Mode(
            // monad builder keywords (matches before non-bang keywords)
            scope: "keyword",
            match: #"\b(yield|return|let|do|match|use)!"#
        )

        let preprocessorKeywords = [
            "if",
            "else",
            "endif",
            "line",
            "nowarn",
            "light",
            "r",
            "i",
            "I",
            "load",
            "time",
            "help",
            "quit",
        ]

        let literals = [
            "true",
            "false",
            "null",
            "Some",
            "None",
            "Ok",
            "Error",
            "infinity",
            "infinityf",
            "nan",
            "nanf",
        ]

        let specialIdentifiers = [
            "__LINE__",
            "__SOURCE_DIRECTORY__",
            "__SOURCE_FILE__",
        ]

        // Since it's possible to re-bind/shadow names (e.g. let char = 'c'),
        // these builtin types should only be matched when a type name is expected.
        let knownTypes = [
            // basic types
            "bool",
            "byte",
            "sbyte",
            "int8",
            "int16",
            "int32",
            "uint8",
            "uint16",
            "uint32",
            "int",
            "uint",
            "int64",
            "uint64",
            "nativeint",
            "unativeint",
            "decimal",
            "float",
            "double",
            "float32",
            "single",
            "char",
            "string",
            "unit",
            "bigint",
            // other native types or lowercase aliases
            "option",
            "voption",
            "list",
            "array",
            "seq",
            "byref",
            "exn",
            "inref",
            "nativeptr",
            "obj",
            "outref",
            "voidptr",
            // other important FSharp types
            "Result",
        ]

        let builtIns = [
            // Somewhat arbitrary list of builtin functions and values.
            // Most of them are declared in Microsoft.FSharp.Core
            "not",
            "ref",
            "raise",
            "reraise",
            "dict",
            "readOnlyDict",
            "set",
            "get",
            "enum",
            "sizeof",
            "typeof",
            "typedefof",
            "nameof",
            "nullArg",
            "invalidArg",
            "invalidOp",
            "id",
            "fst",
            "snd",
            "ignore",
            "lock",
            "using",
            "box",
            "unbox",
            "tryUnbox",
            "printf",
            "printfn",
            "sprintf",
            "eprintf",
            "eprintfn",
            "fprintf",
            "fprintfn",
            "failwith",
            "failwithf",
        ]

        let allKeywords = Keywords([
            "keyword": Keywords.Group(words: keywords),
            "literal": Keywords.Group(words: literals),
            "built_in": Keywords.Group(words: builtIns),
            "variable.constant": Keywords.Group(words: specialIdentifiers),
        ])

        // hljs.inherit(ALL_KEYWORDS, { type: KNOWN_TYPES })
        var allKeywordsWithTypes = allKeywords
        allKeywordsWithTypes.groups["type"] = Keywords.Group(words: knownTypes)

        // (* potentially multi-line Meta Language style comment *)
        let mlComment = CommonModes.comment(#"\(\*(?!\))"#, #"\*\)"#) {
            $0.contains = [Mode.selfReference]
        }
        // Either a multi-line (* Meta Language style comment *) or a single
        // line // C style comment.
        let comment = Mode(variants: [
            mlComment,
            CommonModes.cLineCommentMode,
        ])

        // Most identifiers can contain apostrophes
        let identifierRe = #"[a-zA-Z_](\w|')*"#

        let quotedIdentifier = Mode(
            scope: "variable",
            begin: "``",
            end: "``"
        )

        // 'a or ^a where a can be a ``quoted identifier``
        let beginGenericTypeSymbolRe = #"\B('|\^)"#
        let genericTypeSymbol = Mode(
            scope: "symbol",
            variants: [
                // the type name is a quoted identifier:
                Mode(match: .re(beginGenericTypeSymbolRe + "``.*?``")),
                // the type name is a normal identifier (we don't use
                // IDENTIFIER_RE because there cannot be another apostrophe here):
                Mode(match: .re(beginGenericTypeSymbolRe + CommonModes.underscoreIdentRe)),
            ],
            relevance: 0
        )

        func makeOperatorMode(includeEqual: Bool) -> Mode {
            // List of symbolic operator characters from the FSharp Spec 4.1,
            // minus the dot, and with `?` added, used for nullable operators.
            let allOperatorChars = includeEqual ? "!%&*+-/<=>@^|~?" : "!%&*+-/<>@^|~?"
            let operatorCharRe = "[" + allOperatorChars.map { RegexSource.escape(String($0)) }.joined() + "]"
            // The lone dot operator is special. It cannot be redefined, and we
            // don't want to highlight it. It can be used as part of a
            // multi-chars operator though.
            let operatorCharOrDotRe = RegexSource.either(operatorCharRe, #"\."#)
            // When a dot is present, it must be followed by another operator char:
            let operatorFirstCharOfMultipleRe = operatorCharOrDotRe + RegexSource.lookahead(operatorCharOrDotRe)
            let symbolicOperatorRe = RegexSource.either(
                operatorFirstCharOfMultipleRe + operatorCharOrDotRe + "*", // Matches at least 2 chars operators
                operatorCharRe + "+" // Matches at least one char operators
            )
            return Mode(
                scope: "operator",
                match: .re(RegexSource.either(
                    // symbolic operators:
                    symbolicOperatorRe,
                    // other symbolic keywords:
                    // Type casting and conversion operators:
                    #":\?>"#,
                    #":\?"#,
                    ":>",
                    ":=", // Reference cell assignment
                    "::?", // : or ::
                    #"\$"# // A single $ can be used as an operator
                )),
                relevance: 0
            )
        }

        let operatorMode = makeOperatorMode(includeEqual: true)
        // This variant is used when matching '=' should end a parent mode:
        let operatorWithoutEqual = makeOperatorMode(includeEqual: false)

        func makeTypeAnnotationMode(prefix: String, prefixScope: String) -> Mode {
            Mode(
                begin: .re( // a type annotation is a
                    prefix // should be a colon or the 'of' keyword
                    + RegexSource.lookahead( // that has to be followed by
                        #"\s*"# // optional space
                        + RegexSource.either( // then either of:
                            #"\w"#, // word
                            "'", // generic type name
                            #"\^"#, // generic type name
                            "#", // flexible type name
                            "``", // quoted type name
                            #"\("#, // parens type expression
                            #"\{\|"# // anonymous type annotation
                        )
                    )
                ),
                beginScope: .name(prefixScope),
                // BUG (upstream): because ending with \n is necessary for some
                // cases, multi-line type annotations are not properly supported.
                end: .re(RegexSource.lookahead(RegexSource.either(#"\n"#, "="))),
                // we need the known types, and we need the type constraint
                // keywords and literals. e.g.: when 'a : null
                keywords: allKeywordsWithTypes,
                contains: [
                    comment,
                    genericTypeSymbol,
                    // match to avoid strange patterns inside that may break the parsing
                    quotedIdentifier.copied { $0.scope = ScopeRef.none },
                    operatorWithoutEqual,
                ],
                relevance: 0
            )
        }

        let typeAnnotation = makeTypeAnnotationMode(prefix: ":", prefixScope: "operator")
        let discriminatedUnionTypeAnnotation = makeTypeAnnotationMode(prefix: #"\bof\b"#, prefixScope: "keyword")

        // type MyType<'a> = ...
        let typeDeclaration = Mode(
            begin: [
                #"(^|\s+)"#, // prevents matching the following: `match s.stype with`
                "type",
                #"\s+"#,
                identifierRe,
            ],
            beginScope: [
                2: "keyword",
                4: "title.class",
            ],
            end: .re(RegexSource.lookahead(#"\(|=|$"#)),
            keywords: allKeywords, // match keywords in type constraints. e.g.: when 'a : null
            contains: [
                comment,
                // match to avoid strange patterns inside that may break the parsing
                quotedIdentifier.copied { $0.scope = ScopeRef.none },
                genericTypeSymbol,
                Mode(
                    // For visual consistency, highlight type brackets as operators.
                    scope: "operator",
                    match: "<|>"
                ),
                // generic types can have constraints, which are type annotations.
                // e.g. type MyType<'T when 'T : delegate<obj * string>> =
                typeAnnotation,
            ]
        )

        let computationExpression = Mode(
            // computation expressions:
            scope: "computation-expression",
            // BUG (upstream): might conflict with record deconstruction.
            match: #"\b[_a-z]\w*(?=\s*\{)"#
        )

        let preprocessor = Mode(
            // preprocessor directives and fsi commands:
            begin: [
                #"^\s*"#,
                "#" + RegexSource.either(preprocessorKeywords),
                #"\b"#,
            ],
            beginScope: [2: "meta"],
            end: .re(RegexSource.lookahead(#"\s|$"#))
        )

        // TODO (upstream): this definition is missing support for type
        // suffixes and octal notation.
        // BUG (upstream): range operator without any space is wrongly
        // interpreted as a single number (e.g. 1..10)
        let number = Mode(
            variants: [
                CommonModes.binaryNumberMode,
                CommonModes.cNumberMode,
            ]
        )

        // All the following string definitions are potentially multi-line.
        // BUG (upstream): these definitions are missing support for byte
        // strings (suffixed with B)

        // "..."
        let quotedString = Mode(
            scope: "string",
            begin: "\"",
            end: "\"",
            contains: [
                CommonModes.backslashEscape,
            ]
        )
        // @"..."
        let verbatimString = Mode(
            scope: "string",
            begin: "@\"",
            end: "\"",
            contains: [
                Mode(match: "\"\""), // escaped "
                CommonModes.backslashEscape,
            ]
        )
        // """..."""
        let tripleQuotedString = Mode(
            scope: "string",
            begin: "\"\"\"",
            end: "\"\"\"",
            relevance: 2
        )
        let subst = Mode(
            scope: "subst",
            begin: #"\{"#,
            end: #"\}"#,
            keywords: allKeywords
        )
        // $"...{1+1}..."
        let interpolatedString = Mode(
            scope: "string",
            begin: #"\$""#,
            end: "\"",
            contains: [
                Mode(match: #"\{\{"#), // escaped {
                Mode(match: #"\}\}"#), // escaped }
                CommonModes.backslashEscape,
                subst,
            ]
        )
        // $@"...{1+1}..."
        let interpolatedVerbatimString = Mode(
            scope: "string",
            begin: #"(\$@|@\$)""#,
            end: "\"",
            contains: [
                Mode(match: #"\{\{"#), // escaped {
                Mode(match: #"\}\}"#), // escaped }
                Mode(match: "\"\""),
                CommonModes.backslashEscape,
                subst,
            ]
        )
        // $"""...{1+1}..."""
        let interpolatedTripleQuotedString = Mode(
            scope: "string",
            begin: #"\$""""#,
            end: "\"\"\"",
            contains: [
                Mode(match: #"\{\{"#), // escaped {
                Mode(match: #"\}\}"#), // escaped }
                subst,
            ],
            relevance: 2
        )
        // '.'
        let charLiteral = Mode(
            scope: "string",
            match: .re(
                "'"
                + RegexSource.either(
                    #"[^\\']"#, // either a single non escaped char...
                    #"\\(?:.|\d{3}|x[a-fA-F\d]{2}|u[a-fA-F\d]{4}|U[a-fA-F\d]{8})"# // ...or an escape sequence
                )
                + "'"
            )
        )
        // F# allows a lot of things inside string placeholders.
        // Things that don't currently seem allowed by the compiler: types
        // definition, attributes usage.
        subst.contains = [
            interpolatedVerbatimString,
            interpolatedString,
            verbatimString,
            quotedString,
            charLiteral,
            bangKeywordMode,
            comment,
            quotedIdentifier,
            typeAnnotation,
            computationExpression,
            preprocessor,
            number,
            genericTypeSymbol,
            operatorMode,
        ]
        let string = Mode(
            variants: [
                interpolatedTripleQuotedString,
                interpolatedVerbatimString,
                interpolatedString,
                tripleQuotedString,
                verbatimString,
                quotedString,
                charLiteral,
            ]
        )

        return LanguageDefinition(
            name: "fsharp",
            aliases: ["fs", "f#"],
            classNameAliases: [
                "computation-expression": "keyword",
            ],
            root: Mode(
                keywords: allKeywords,
                illegal: [#"\/\*"#],
                contains: [
                    bangKeywordMode,
                    string,
                    comment,
                    quotedIdentifier,
                    typeDeclaration,
                    Mode(
                        // e.g. [<Attributes("")>]
                        // or [<``module``: MyCustomAttributeThatWorksOnModules>]
                        // or [<Sealed; NoEquality; NoComparison; CompiledName("FSharpAsync`1")>]
                        scope: "meta",
                        begin: #"\[<"#,
                        end: #">\]"#,
                        contains: [
                            quotedIdentifier,
                            // can contain any constant value
                            tripleQuotedString,
                            verbatimString,
                            quotedString,
                            charLiteral,
                            number,
                        ],
                        relevance: 2
                    ),
                    discriminatedUnionTypeAnnotation,
                    typeAnnotation,
                    computationExpression,
                    preprocessor,
                    number,
                    genericTypeSymbol,
                    operatorMode,
                ]
            )
        )
    }
}
