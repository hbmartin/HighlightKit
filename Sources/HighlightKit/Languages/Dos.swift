import Foundation

extension LanguageCatalog {
    /// Batch file (DOS). Port of highlight.js `languages/dos.js`.
    public static let dos = LanguageDescriptor(name: "dos", aliases: ["bat", "cmd"]) {
        let comment = CommonModes.comment(#"^\s*@?rem\b"#, "$") { m in
            m.relevance = 10
        }
        let labelBegin = "^\\s*[A-Za-z._?][A-Za-z0-9_$#@~.?]*(:|\\s+label)"

        let keywords = [
            "if",
            "else",
            "goto",
            "for",
            "in",
            "do",
            "call",
            "exit",
            "not",
            "exist",
            "errorlevel",
            "defined",
            "equ",
            "neq",
            "lss",
            "leq",
            "gtr",
            "geq",
        ]
        let builtIns = [
            "prn",
            "nul",
            "lpt3",
            "lpt2",
            "lpt1",
            "con",
            "com4",
            "com3",
            "com2",
            "com1",
            "aux",
            "shift",
            "cd",
            "dir",
            "echo",
            "setlocal",
            "endlocal",
            "set",
            "pause",
            "copy",
            "append",
            "assoc",
            "at",
            "attrib",
            "break",
            "cacls",
            "cd",
            "chcp",
            "chdir",
            "chkdsk",
            "chkntfs",
            "cls",
            "cmd",
            "color",
            "comp",
            "compact",
            "convert",
            "date",
            "dir",
            "diskcomp",
            "diskcopy",
            "doskey",
            "erase",
            "fs",
            "find",
            "findstr",
            "format",
            "ftype",
            "graftabl",
            "help",
            "keyb",
            "label",
            "md",
            "mkdir",
            "mode",
            "more",
            "move",
            "path",
            "pause",
            "print",
            "popd",
            "pushd",
            "promt",
            "rd",
            "recover",
            "rem",
            "rename",
            "replace",
            "restore",
            "rmdir",
            "shift",
            "sort",
            "start",
            "subst",
            "time",
            "title",
            "tree",
            "type",
            "ver",
            "verify",
            "vol",
            // winutils
            "ping",
            "net",
            "ipconfig",
            "taskkill",
            "xcopy",
            "ren",
            "del",
        ]

        return LanguageDefinition(
            name: "dos",
            aliases: ["bat", "cmd"],
            caseInsensitive: true,
            root: Mode(
                keywords: Keywords([
                    "keyword": Keywords.Group(words: keywords),
                    "built_in": Keywords.Group(words: builtIns),
                ]),
                illegal: [#"/\*"#],
                contains: [
                    Mode(
                        scope: "variable",
                        begin: #"%%[^ ]|%[^ ]+?%|![^ ]+?!"#
                    ),
                    Mode(
                        scope: "function",
                        begin: .re(labelBegin),
                        end: "goto:eof",
                        contains: [
                            { let m = CommonModes.titleMode; m.begin = "([_a-zA-Z]\\w*\\.)*([_a-zA-Z]\\w*:)?[_a-zA-Z]\\w*"; return m }(),
                            comment,
                        ]
                    ),
                    Mode(
                        scope: "number",
                        begin: "\\b\\d+",
                        relevance: 0
                    ),
                    comment,
                ]
            )
        )
    }
}
