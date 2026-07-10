import Foundation

extension LanguageCatalog {
    /// Bash. Port of highlight.js `languages/bash.js`.
    public static let bash = LanguageDescriptor(name: "bash", aliases: ["sh", "zsh"]) {
        let varMode = Mode(scope: "variable")
        let bracedVar = Mode(
            begin: #"\$\{"#,
            end: #"\}"#,
            contains: [
                Mode.selfReference,
                Mode(begin: ":-", contains: [varMode]), // default values
            ]
        )
        varMode.variants = [
            // negative look-ahead tries to avoid matching patterns that are not
            // Perl at all like $ident$, @ident@, etc.
            Mode(begin: #"\$[\w\d#@][\w\d_]*(?![\w\d])(?![$])"#),
            bracedVar,
        ]

        let subst = Mode(
            scope: "subst",
            begin: #"\$\("#,
            end: #"\)"#,
            contains: [CommonModes.backslashEscape]
        )
        let comment = CommonModes.comment("", "") { m in
            m.begin = nil
            m.end = nil
            m.match = [#"(^|\s)"#, "#.*$"]
            m.scope = [2: "comment"]
        }
        let hereDoc = Mode(
            begin: #"<<-?\s*(?=\w+)"#,
            starts: Mode(contains: [
                Mode(
                    scope: "string",
                    begin: #"(\w+)"#,
                    end: #"(\w+)"#,
                    endSameAsBegin: true
                ),
            ])
        )
        let quoteString = Mode(
            scope: "string",
            begin: "\"",
            end: "\"",
            contains: [
                CommonModes.backslashEscape,
                varMode,
                subst,
            ]
        )
        subst.contains?.append(quoteString)
        let escapedQuote = Mode(match: #"\\""#)
        let aposString = Mode(scope: "string", begin: "'", end: "'")
        let escapedApos = Mode(match: #"\\'"#)
        let arithmetic = Mode(
            begin: #"\$?\(\("#,
            end: #"\)\)"#,
            contains: [
                Mode(scope: "number", begin: "\\d+#[0-9a-f]+"),
                CommonModes.numberMode,
                varMode,
            ]
        )
        let shLikeShells = [
            "fish",
            "bash",
            "zsh",
            "sh",
            "csh",
            "ksh",
            "tcsh",
            "dash",
            "scsh",
        ]
        let knownShebang = CommonModes.shebang(
            binary: "(" + shLikeShells.joined(separator: "|") + ")",
            relevance: 10
        )
        let function = Mode(
            scope: "function",
            begin: #"\w[\w\d_]*\s*\(\s*\)\s*\{"#,
            contains: [
                { let m = CommonModes.titleMode; m.begin = #"\w[\w\d_]*"#; return m }(),
            ],
            relevance: 0,
            returnBegin: true
        )

        let keywords = [
            "if",
            "then",
            "else",
            "elif",
            "fi",
            "time",
            "for",
            "while",
            "until",
            "in",
            "do",
            "done",
            "case",
            "esac",
            "coproc",
            "function",
            "select",
        ]

        let literals = [
            "true",
            "false",
        ]

        // to consume paths to prevent keyword matches inside them
        let pathMode = Mode(match: "(\\/[a-z._-]+)+")

        // http://www.gnu.org/software/bash/manual/html_node/Shell-Builtin-Commands.html
        let shellBuiltIns = [
            "break",
            "cd",
            "continue",
            "eval",
            "exec",
            "exit",
            "export",
            "getopts",
            "hash",
            "pwd",
            "readonly",
            "return",
            "shift",
            "test",
            "times",
            "trap",
            "umask",
            "unset",
        ]

        let bashBuiltIns = [
            "alias",
            "bind",
            "builtin",
            "caller",
            "command",
            "declare",
            "echo",
            "enable",
            "help",
            "let",
            "local",
            "logout",
            "mapfile",
            "printf",
            "read",
            "readarray",
            "source",
            "sudo",
            "type",
            "typeset",
            "ulimit",
            "unalias",
        ]

        let zshBuiltIns = [
            "autoload",
            "bg",
            "bindkey",
            "bye",
            "cap",
            "chdir",
            "clone",
            "comparguments",
            "compcall",
            "compctl",
            "compdescribe",
            "compfiles",
            "compgroups",
            "compquote",
            "comptags",
            "comptry",
            "compvalues",
            "dirs",
            "disable",
            "disown",
            "echotc",
            "echoti",
            "emulate",
            "fc",
            "fg",
            "float",
            "functions",
            "getcap",
            "getln",
            "history",
            "integer",
            "jobs",
            "kill",
            "limit",
            "log",
            "noglob",
            "popd",
            "print",
            "pushd",
            "pushln",
            "rehash",
            "sched",
            "setcap",
            "setopt",
            "stat",
            "suspend",
            "ttyctl",
            "unfunction",
            "unhash",
            "unlimit",
            "unsetopt",
            "vared",
            "wait",
            "whence",
            "where",
            "which",
            "zcompile",
            "zformat",
            "zftp",
            "zle",
            "zmodload",
            "zparseopts",
            "zprof",
            "zpty",
            "zregexparse",
            "zsocket",
            "zstyle",
            "ztcp",
        ]

        let gnuCoreUtils = [
            "chcon",
            "chgrp",
            "chown",
            "chmod",
            "cp",
            "dd",
            "df",
            "dir",
            "dircolors",
            "ln",
            "ls",
            "mkdir",
            "mkfifo",
            "mknod",
            "mktemp",
            "mv",
            "realpath",
            "rm",
            "rmdir",
            "shred",
            "sync",
            "touch",
            "truncate",
            "vdir",
            "b2sum",
            "base32",
            "base64",
            "cat",
            "cksum",
            "comm",
            "csplit",
            "cut",
            "expand",
            "fmt",
            "fold",
            "head",
            "join",
            "md5sum",
            "nl",
            "numfmt",
            "od",
            "paste",
            "ptx",
            "pr",
            "sha1sum",
            "sha224sum",
            "sha256sum",
            "sha384sum",
            "sha512sum",
            "shuf",
            "sort",
            "split",
            "sum",
            "tac",
            "tail",
            "tr",
            "tsort",
            "unexpand",
            "uniq",
            "wc",
            "arch",
            "basename",
            "chroot",
            "date",
            "dirname",
            "du",
            "echo",
            "env",
            "expr",
            "factor",
            // "false", // keyword literal already
            "groups",
            "hostid",
            "id",
            "link",
            "logname",
            "nice",
            "nohup",
            "nproc",
            "pathchk",
            "pinky",
            "printenv",
            "printf",
            "pwd",
            "readlink",
            "runcon",
            "seq",
            "sleep",
            "stat",
            "stdbuf",
            "stty",
            "tee",
            "test",
            "timeout",
            // "true", // keyword literal already
            "tty",
            "uname",
            "unlink",
            "uptime",
            "users",
            "who",
            "whoami",
            "yes",
        ]

        return LanguageDefinition(
            name: "bash",
            aliases: ["sh", "zsh"],
            root: Mode(
                keywords: Keywords(
                    pattern: #"\b[a-z][a-z0-9._-]+\b"#,
                    [
                        "keyword": Keywords.Group(words: keywords),
                        "literal": Keywords.Group(words: literals),
                        "built_in": Keywords.Group(
                            words: shellBuiltIns
                                + bashBuiltIns
                                // Shell modifiers
                                + ["set", "shopt"]
                                + zshBuiltIns
                                + gnuCoreUtils
                        ),
                    ]
                ),
                contains: [
                    knownShebang, // to catch known shells and boost relevancy
                    CommonModes.shebang(), // to catch unknown shells but still highlight the shebang
                    function,
                    arithmetic,
                    comment,
                    hereDoc,
                    pathMode,
                    quoteString,
                    escapedQuote,
                    aposString,
                    escapedApos,
                    varMode,
                ]
            )
        )
    }
}
