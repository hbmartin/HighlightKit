import Foundation

extension LanguageCatalog {
    /// Objective-C. Port of highlight.js `languages/objectivec.js`.
    public static let objectivec = LanguageDescriptor(name: "objectivec", aliases: ["mm", "objc", "obj-c", "obj-c++", "objective-c++"]) {
        let apiClass = Mode(
            scope: "built_in",
            begin: #"\b(AV|CA|CF|CG|CI|CL|CM|CN|CT|MK|MP|MTK|MTL|NS|SCN|SK|UI|WK|XC)\w+"#
        )
        let identifierRe = "[a-zA-Z@][a-zA-Z0-9_]*"
        let types = [
            "int",
            "float",
            "char",
            "unsigned",
            "signed",
            "short",
            "long",
            "double",
            "wchar_t",
            "unichar",
            "void",
            "bool",
            "BOOL",
            "id|0",
            "_Bool",
        ]
        let kws = [
            "while",
            "export",
            "sizeof",
            "typedef",
            "const",
            "struct",
            "for",
            "union",
            "volatile",
            "static",
            "mutable",
            "if",
            "do",
            "return",
            "goto",
            "enum",
            "else",
            "break",
            "extern",
            "asm",
            "case",
            "default",
            "register",
            "explicit",
            "typename",
            "switch",
            "continue",
            "inline",
            "readonly",
            "assign",
            "readwrite",
            "self",
            "@synchronized",
            "id",
            "typeof",
            "nonatomic",
            "IBOutlet",
            "IBAction",
            "strong",
            "weak",
            "copy",
            "in",
            "out",
            "inout",
            "bycopy",
            "byref",
            "oneway",
            "__strong",
            "__weak",
            "__block",
            "__autoreleasing",
            "@private",
            "@protected",
            "@public",
            "@try",
            "@property",
            "@end",
            "@throw",
            "@catch",
            "@finally",
            "@autoreleasepool",
            "@synthesize",
            "@dynamic",
            "@selector",
            "@optional",
            "@required",
            "@encode",
            "@package",
            "@import",
            "@defs",
            "@compatibility_alias",
            "__bridge",
            "__bridge_transfer",
            "__bridge_retained",
            "__bridge_retain",
            "__covariant",
            "__contravariant",
            "__kindof",
            "_Nonnull",
            "_Nullable",
            "_Null_unspecified",
            "__FUNCTION__",
            "__PRETTY_FUNCTION__",
            "__attribute__",
            "getter",
            "setter",
            "retain",
            "unsafe_unretained",
            "nonnull",
            "nullable",
            "null_unspecified",
            "null_resettable",
            "class",
            "instancetype",
            "NS_DESIGNATED_INITIALIZER",
            "NS_UNAVAILABLE",
            "NS_REQUIRES_SUPER",
            "NS_RETURNS_INNER_POINTER",
            "NS_INLINE",
            "NS_AVAILABLE",
            "NS_DEPRECATED",
            "NS_ENUM",
            "NS_OPTIONS",
            "NS_SWIFT_UNAVAILABLE",
            "NS_ASSUME_NONNULL_BEGIN",
            "NS_ASSUME_NONNULL_END",
            "NS_REFINED_FOR_SWIFT",
            "NS_SWIFT_NAME",
            "NS_SWIFT_NOTHROW",
            "NS_DURING",
            "NS_HANDLER",
            "NS_ENDHANDLER",
            "NS_VALUERETURN",
            "NS_VOIDRETURN",
        ]
        let literals = [
            "false",
            "true",
            "FALSE",
            "TRUE",
            "nil",
            "YES",
            "NO",
            "NULL",
        ]
        let builtIns = [
            "dispatch_once_t",
            "dispatch_queue_t",
            "dispatch_sync",
            "dispatch_async",
            "dispatch_once",
        ]
        // "id" appears in both KWS (keyword) and TYPES ("id|0").
        // highlight.js compiles keyword groups in insertion order, so the
        // later `type` entry wins; `Keywords.groups` is an unordered
        // dictionary, so drop the shadowed keyword entry to reproduce the
        // same compiled table deterministically.
        let keywords = Keywords(
            pattern: identifierRe,
            [
                "variable.language": ["this", "super"],
                "keyword": Keywords.Group(words: kws.filter { $0 != "id" }),
                "literal": Keywords.Group(words: literals),
                "built_in": Keywords.Group(words: builtIns),
                "type": Keywords.Group(words: types),
            ]
        )
        let classKeywords = Keywords(
            pattern: identifierRe,
            keyword: ["@interface", "@class", "@protocol", "@implementation"]
        )
        return LanguageDefinition(
            name: "objectivec",
            aliases: [
                "mm",
                "objc",
                "obj-c",
                "obj-c++",
                "objective-c++",
            ],
            root: Mode(
                keywords: keywords,
                illegal: ["</"],
                contains: [
                    apiClass,
                    CommonModes.cLineCommentMode,
                    CommonModes.cBlockCommentMode,
                    CommonModes.cNumberMode,
                    CommonModes.quoteStringMode,
                    CommonModes.aposStringMode,
                    Mode(
                        scope: "string",
                        variants: [
                            Mode(
                                begin: "@\"",
                                end: "\"",
                                illegal: [#"\n"#],
                                contains: [CommonModes.backslashEscape]
                            ),
                        ]
                    ),
                    Mode(
                        scope: "meta",
                        begin: #"#\s*[a-z]+\b"#,
                        end: "$",
                        keywords: Keywords(
                            keyword: Keywords.Group(stringLiteral:
                                "if else elif endif define undef warning error line "
                                + "pragma ifdef ifndef include"
                            )
                        ),
                        contains: [
                            Mode(begin: #"\\\n"#, relevance: 0),
                            CommonModes.quoteStringMode.copied { $0.scope = "string" },
                            Mode(
                                scope: "string",
                                begin: "<.*?>",
                                end: "$",
                                illegal: [#"\n"#]
                            ),
                            CommonModes.cLineCommentMode,
                            CommonModes.cBlockCommentMode,
                        ]
                    ),
                    Mode(
                        scope: "class",
                        begin: #"(@interface|@class|@protocol|@implementation)\b"#,
                        end: #"(\{|$)"#,
                        keywords: classKeywords,
                        contains: [CommonModes.underscoreTitleMode],
                        excludeEnd: true
                    ),
                    Mode(
                        begin: .re(#"\."# + CommonModes.underscoreIdentRe),
                        relevance: 0
                    ),
                ]
            )
        )
    }
}
