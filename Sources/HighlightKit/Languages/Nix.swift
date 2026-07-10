import Foundation

extension LanguageCatalog {
    /// Nix. Port of highlight.js `languages/nix.js`.
    public static let nix = LanguageDescriptor(name: "nix", aliases: ["nixos"]) {
        let keywords = Keywords([
            "keyword": Keywords.Group(words: [
                "assert",
                "else",
                "if",
                "in",
                "inherit",
                "let",
                "or",
                "rec",
                "then",
                "with",
            ]),
            "literal": Keywords.Group(words: [
                "true",
                "false",
                "null",
            ]),
            "built_in": Keywords.Group(words: [
                // toplevel builtins
                "abort",
                "baseNameOf",
                "builtins",
                "derivation",
                "derivationStrict",
                "dirOf",
                "fetchGit",
                "fetchMercurial",
                "fetchTarball",
                "fetchTree",
                "fromTOML",
                "import",
                "isNull",
                "map",
                "placeholder",
                "removeAttrs",
                "scopedImport",
                "throw",
                "toString",
            ]),
        ])

        let builtinNames = [
            "abort",
            "add",
            "addDrvOutputDependencies",
            "addErrorContext",
            "all",
            "any",
            "appendContext",
            "attrNames",
            "attrValues",
            "baseNameOf",
            "bitAnd",
            "bitOr",
            "bitXor",
            "break",
            "builtins",
            "catAttrs",
            "ceil",
            "compareVersions",
            "concatLists",
            "concatMap",
            "concatStringsSep",
            "convertHash",
            "currentSystem",
            "currentTime",
            "deepSeq",
            "derivation",
            "derivationStrict",
            "dirOf",
            "div",
            "elem",
            "elemAt",
            "false",
            "fetchGit",
            "fetchMercurial",
            "fetchTarball",
            "fetchTree",
            "fetchurl",
            "filter",
            "filterSource",
            "findFile",
            "flakeRefToString",
            "floor",
            "foldl'",
            "fromJSON",
            "fromTOML",
            "functionArgs",
            "genList",
            "genericClosure",
            "getAttr",
            "getContext",
            "getEnv",
            "getFlake",
            "groupBy",
            "hasAttr",
            "hasContext",
            "hashFile",
            "hashString",
            "head",
            "import",
            "intersectAttrs",
            "isAttrs",
            "isBool",
            "isFloat",
            "isFunction",
            "isInt",
            "isList",
            "isNull",
            "isPath",
            "isString",
            "langVersion",
            "length",
            "lessThan",
            "listToAttrs",
            "map",
            "mapAttrs",
            "match",
            "mul",
            "nixPath",
            "nixVersion",
            "null",
            "parseDrvName",
            "parseFlakeRef",
            "partition",
            "path",
            "pathExists",
            "placeholder",
            "readDir",
            "readFile",
            "readFileType",
            "removeAttrs",
            "replaceStrings",
            "scopedImport",
            "seq",
            "sort",
            "split",
            "splitVersion",
            "storeDir",
            "storePath",
            "stringLength",
            "sub",
            "substring",
            "tail",
            "throw",
            "toFile",
            "toJSON",
            "toPath",
            "toString",
            "toXML",
            "trace",
            "traceVerbose",
            "true",
            "tryEval",
            "typeOf",
            "unsafeDiscardOutputDependency",
            "unsafeDiscardStringContext",
            "unsafeGetAttrPos",
            "warn",
            "zipAttrsWith",
        ]
        let builtins = Mode(
            scope: "built_in",
            match: .re(RegexSource.either(builtinNames.map { #"builtins\."# + $0 })),
            relevance: 10
        )

        let identifierRegex = "[A-Za-z_][A-Za-z0-9_'-]*"

        let lookupPath = Mode(
            scope: "symbol",
            match: .re("<\(identifierRegex)(/\(identifierRegex))*>")
        )

        let pathPiece = #"[A-Za-z0-9_\+\.-]+"#
        let path = Mode(
            scope: "symbol",
            match: .re(#"(\.\.|\.|~)?/(\#(pathPiece))?(/\#(pathPiece))*(?=[\s;])"#)
        )

        let operatorWithoutMinusRegex = RegexSource.either([
            "==",
            "=",
            #"\+\+"#,
            #"\+"#,
            "<=",
            #"<\|"#,
            "<",
            ">=",
            ">",
            "->",
            "//",
            "/",
            "!=",
            "!",
            #"\|\|"#,
            #"\|>"#,
            #"\?"#,
            #"\*"#,
            "&&",
        ])

        let operatorMode = Mode(
            scope: "operator",
            match: .re(RegexSource.concat(operatorWithoutMinusRegex, "(?!-)")),
            relevance: 0
        )

        // '-' is being handled by itself to ensure we are able to tell the
        // difference between a dash in an identifier and a minus operator
        let number = Mode(
            scope: "number",
            match: .re("\(CommonModes.numberRe)(?!-)"),
            relevance: 0
        )
        let minusOperator = Mode(
            variants: [
                Mode(
                    scope: "operator",
                    // The (?!>) is used to ensure this doesn't collide with
                    // the '->' operator
                    begin: "-(?!>)",
                    beforeMatch: #"\s"#
                ),
                Mode(
                    begin: .parts([
                        CommonModes.numberRe,
                        "-",
                        "(?!>)",
                    ]),
                    beginScope: [
                        1: "number",
                        2: "operator",
                    ]
                ),
                Mode(
                    begin: .parts([
                        operatorWithoutMinusRegex,
                        "-",
                        "(?!>)",
                    ]),
                    beginScope: [
                        1: "operator",
                        2: "operator",
                    ]
                ),
            ],
            relevance: 0
        )

        let attrs = Mode(
            begin: .re("\(identifierRegex)(\\.\(identifierRegex))*\\s*=(?!=)"),
            beforeMatch: #"(^|\{|;)\s*"#,
            contains: [
                Mode(
                    scope: "attr",
                    match: .re("\(identifierRegex)(\\.\(identifierRegex))*(?=\\s*=)"),
                    relevance: 0.2
                ),
            ],
            relevance: 0,
            returnBegin: true
        )

        let normalEscapedDollar = Mode(
            scope: "char.escape",
            match: #"\\\$"#
        )
        let indentedEscapedDollar = Mode(
            scope: "char.escape",
            match: #"''\$"#
        )
        let antiquote = Mode(
            scope: "subst",
            begin: #"\$\{"#,
            end: #"\}"#,
            keywords: keywords
        )
        let escapedDoublequote = Mode(
            scope: "char.escape",
            match: "'''"
        )
        let escapedLiteral = Mode(
            scope: "char.escape",
            match: #"\\(?!\$)."#
        )
        let string = Mode(
            scope: "string",
            variants: [
                Mode(
                    begin: "''",
                    end: "''",
                    contains: [
                        indentedEscapedDollar,
                        antiquote,
                        escapedDoublequote,
                        escapedLiteral,
                    ]
                ),
                Mode(
                    begin: "\"",
                    end: "\"",
                    contains: [
                        normalEscapedDollar,
                        antiquote,
                        escapedLiteral,
                    ]
                ),
            ]
        )

        let functionParams = Mode(
            scope: "params",
            match: .re("\(identifierRegex)\\s*:(?=\\s)")
        )

        let expressions: [Mode] = [
            number,
            CommonModes.hashCommentMode,
            CommonModes.cBlockCommentMode,
            CommonModes.comment(#"\/\*\*(?!\/)"#, #"\*\/"#) { m in
                m.subLanguage = ["markdown"]
                m.relevance = 0
            },
            builtins,
            string,
            lookupPath,
            path,
            functionParams,
            attrs,
            minusOperator,
            operatorMode,
        ]

        antiquote.contains = expressions

        let repl: [Mode] = [
            Mode(
                scope: "meta.prompt",
                match: #"^nix-repl>(?=\s)"#,
                relevance: 10
            ),
            Mode(
                scope: "meta",
                begin: #":([a-z]+|\?)"#,
                beforeMatch: #"\s+"#
            ),
        ]

        return LanguageDefinition(
            name: "nix",
            aliases: ["nixos"],
            root: Mode(
                keywords: keywords,
                contains: expressions + repl
            )
        )
    }
}
