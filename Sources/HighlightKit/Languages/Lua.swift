import Foundation

extension LanguageCatalog {
    /// Lua. Port of highlight.js `languages/lua.js`.
    public static let lua = LanguageDescriptor(name: "lua", aliases: ["pluto"]) {
        let openingLongBracket = #"\[=*\["#
        let closingLongBracket = #"\]=*\]"#
        let longBrackets = Mode(
            begin: .re(openingLongBracket),
            end: .re(closingLongBracket),
            contains: [Mode.selfReference]
        )
        let comments = [
            CommonModes.comment("--(?!" + openingLongBracket + ")", "$"),
            CommonModes.comment("--" + openingLongBracket, closingLongBracket) { mode in
                mode.contains = [longBrackets]
                mode.relevance = 10
            },
        ]
        return LanguageDefinition(
            name: "lua",
            aliases: ["pluto"],
            root: Mode(
                keywords: Keywords(
                    pattern: CommonModes.underscoreIdentRe,
                    [
                        "literal": "true false nil",
                        "keyword": "and break do else elseif end for goto if in local global not or repeat return then until while",
                        "built_in": Keywords.Group(stringLiteral:
                            // Metatags and globals:
                            "_G _ENV _VERSION __index __newindex __mode __call __metatable __tostring __len "
                            + "__gc __add __sub __mul __div __mod __pow __concat __unm __eq __lt __le assert "
                            // Standard methods and properties:
                            + "collectgarbage dofile error getfenv getmetatable ipairs load loadfile loadstring "
                            + "module next pairs pcall print rawequal rawget rawset require select setfenv "
                            + "setmetatable tonumber tostring type unpack xpcall arg self "
                            // Library methods and properties (one line per library):
                            + "coroutine resume yield status wrap create running debug getupvalue "
                            + "debug sethook getmetatable gethook setmetatable setlocal traceback setfenv getinfo setupvalue getlocal getregistry getfenv "
                            + "io lines write close flush open output type read stderr stdin input stdout popen tmpfile "
                            + "math log max acos huge ldexp pi cos tanh pow deg tan cosh sinh random randomseed frexp ceil floor rad abs sqrt modf asin min mod fmod log10 atan2 exp sin atan "
                            + "os exit setlocale date getenv difftime remove time clock tmpname rename execute package preload loadlib loaded loaders cpath config path seeall "
                            + "string sub upper len gfind rep find match char dump gmatch reverse byte format gsub lower "
                            + "table setn insert getn foreachi maxn foreach concat sort remove"
                        ),
                    ]
                ),
                contains: comments + [
                    Mode(
                        scope: "function",
                        beginKeywords: "function",
                        end: #"\)"#,
                        contains: [
                            {
                                let m = CommonModes.titleMode
                                m.begin = .re(#"([_a-zA-Z]\w*\.)*([_a-zA-Z]\w*:)?[_a-zA-Z]\w*"#)
                                return m
                            }(),
                            Mode(
                                scope: "params",
                                begin: #"\("#,
                                contains: comments,
                                endsWithParent: true
                            ),
                        ] + comments
                    ),
                    CommonModes.cNumberMode,
                    CommonModes.aposStringMode,
                    CommonModes.quoteStringMode,
                    Mode(
                        scope: "string",
                        begin: .re(openingLongBracket),
                        end: .re(closingLongBracket),
                        contains: [longBrackets],
                        relevance: 5
                    ),
                ]
            )
        )
    }
}
