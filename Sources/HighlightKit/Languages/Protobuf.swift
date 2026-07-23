import Foundation

extension LanguageCatalog {
    /// Protocol Buffers. Port of highlight.js `languages/protobuf.js` at 08cb242.
    public static let protobuf = LanguageDescriptor(name: "protobuf", aliases: ["proto"]) {
        let keywords = Keywords([
            "keyword": Keywords.Group(words: [
                "package", "import", "option", "optional", "required", "repeated",
                "group", "oneof",
            ]),
            "type": Keywords.Group(words: [
                "double", "float", "int32", "int64", "uint32", "uint64", "sint32",
                "sint64", "fixed32", "fixed64", "sfixed32", "sfixed64", "bool",
                "string", "bytes",
            ]),
            "literal": Keywords.Group(words: ["true", "false"]),
        ])
        let typeDeclaration = Mode(
            scope: [1: "keyword", 2: "title.class"],
            match: [#"(message|enum|service)\s+"#, CommonModes.identRe]
        )
        return LanguageDefinition(
            name: "protobuf",
            aliases: ["proto"],
            root: Mode(
                keywords: keywords,
                contains: [
                    CommonModes.quoteStringMode,
                    CommonModes.numberMode,
                    CommonModes.cLineCommentMode,
                    CommonModes.cBlockCommentMode,
                    typeDeclaration,
                    Mode(
                        scope: "function",
                        beginKeywords: "rpc",
                        end: #"[{;]"#,
                        keywords: "rpc returns",
                        excludeEnd: true
                    ),
                    Mode(begin: #"^\s*[A-Z_]+(?=\s*=[^\n]+;$)"#),
                ]
            )
        )
    }
}
