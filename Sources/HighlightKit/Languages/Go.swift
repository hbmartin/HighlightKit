import Foundation

extension LanguageCatalog {
    /// Go. Port of highlight.js `languages/go.js`.
    public static let go = LanguageDescriptor(name: "go", aliases: ["golang"]) {
        let literals = [
            "true",
            "false",
            "iota",
            "nil",
        ]
        let builtIns = [
            "append",
            "cap",
            "close",
            "complex",
            "copy",
            "imag",
            "len",
            "make",
            "new",
            "panic",
            "print",
            "println",
            "real",
            "recover",
            "delete",
        ]
        let types = [
            "bool",
            "byte",
            "complex64",
            "complex128",
            "error",
            "float32",
            "float64",
            "int8",
            "int16",
            "int32",
            "int64",
            "string",
            "uint8",
            "uint16",
            "uint32",
            "uint64",
            "int",
            "uint",
            "uintptr",
            "rune",
        ]
        let kws = [
            "break",
            "case",
            "chan",
            "const",
            "continue",
            "default",
            "defer",
            "else",
            "fallthrough",
            "for",
            "func",
            "go",
            "goto",
            "if",
            "import",
            "interface",
            "map",
            "package",
            "range",
            "return",
            "select",
            "struct",
            "switch",
            "type",
            "var",
        ]
        let keywords = Keywords([
            "keyword": Keywords.Group(words: kws),
            "type": Keywords.Group(words: types),
            "literal": Keywords.Group(words: literals),
            "built_in": Keywords.Group(words: builtIns),
        ])
        return LanguageDefinition(
            name: "go",
            aliases: ["golang"],
            root: Mode(
                keywords: keywords,
                illegal: ["</"],
                contains: [
                    CommonModes.cLineCommentMode,
                    CommonModes.cBlockCommentMode,
                    Mode(
                        scope: "string",
                        variants: [
                            CommonModes.quoteStringMode,
                            CommonModes.aposStringMode,
                            Mode(begin: "`", end: "`"),
                        ]
                    ),
                    Mode(
                        scope: "number",
                        variants: [
                            // hex without a present digit before . (making a digit afterwards required)
                            Mode(
                                match: #"-?\b0[xX]\.[a-fA-F0-9](_?[a-fA-F0-9])*[pP][+-]?\d(_?\d)*i?"#,
                                relevance: 0
                            ),
                            // hex with a present digit before . (making a digit afterwards optional)
                            Mode(
                                match: #"-?\b0[xX](_?[a-fA-F0-9])+((\.([a-fA-F0-9](_?[a-fA-F0-9])*)?)?[pP][+-]?\d(_?\d)*)?i?"#,
                                relevance: 0
                            ),
                            // leading 0o octal
                            Mode(
                                match: #"-?\b0[oO](_?[0-7])*i?"#,
                                relevance: 0
                            ),
                            // decimal without a present digit before . (making a digit afterwards required)
                            Mode(
                                match: #"-?\.\d(_?\d)*([eE][+-]?\d(_?\d)*)?i?"#,
                                relevance: 0
                            ),
                            // decimal with a present digit before . (making a digit afterwards optional)
                            Mode(
                                match: #"-?\b\d(_?\d)*(\.(\d(_?\d)*)?)?([eE][+-]?\d(_?\d)*)?i?"#,
                                relevance: 0
                            ),
                        ]
                    ),
                    Mode(begin: ":=") // relevance booster
                    ,
                    Mode(
                        scope: "function",
                        beginKeywords: "func",
                        end: #"\s*(\{|$)"#,
                        contains: [
                            CommonModes.titleMode,
                            Mode(
                                scope: "params",
                                begin: #"\("#,
                                end: #"\)"#,
                                keywords: keywords,
                                illegal: [#"["']"#],
                                endsParent: true
                            ),
                        ],
                        excludeEnd: true
                    ),
                ]
            )
        )
    }
}
