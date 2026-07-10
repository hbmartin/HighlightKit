import Foundation

extension LanguageCatalog {
    /// Perl. Port of highlight.js `languages/perl.js`.
    public static let perl = LanguageDescriptor(name: "perl", aliases: ["pl", "pm"]) {
        let keywords = [
            "abs",
            "accept",
            "alarm",
            "and",
            "atan2",
            "bind",
            "binmode",
            "bless",
            "break",
            "caller",
            "chdir",
            "chmod",
            "chomp",
            "chop",
            "chown",
            "chr",
            "chroot",
            "class",
            "close",
            "closedir",
            "connect",
            "continue",
            "cos",
            "crypt",
            "dbmclose",
            "dbmopen",
            "defined",
            "delete",
            "die",
            "do",
            "dump",
            "each",
            "else",
            "elsif",
            "endgrent",
            "endhostent",
            "endnetent",
            "endprotoent",
            "endpwent",
            "endservent",
            "eof",
            "eval",
            "exec",
            "exists",
            "exit",
            "exp",
            "fcntl",
            "field",
            "fileno",
            "flock",
            "for",
            "foreach",
            "fork",
            "format",
            "formline",
            "getc",
            "getgrent",
            "getgrgid",
            "getgrnam",
            "gethostbyaddr",
            "gethostbyname",
            "gethostent",
            "getlogin",
            "getnetbyaddr",
            "getnetbyname",
            "getnetent",
            "getpeername",
            "getpgrp",
            "getpriority",
            "getprotobyname",
            "getprotobynumber",
            "getprotoent",
            "getpwent",
            "getpwnam",
            "getpwuid",
            "getservbyname",
            "getservbyport",
            "getservent",
            "getsockname",
            "getsockopt",
            "given",
            "glob",
            "gmtime",
            "goto",
            "grep",
            "gt",
            "hex",
            "if",
            "index",
            "int",
            "ioctl",
            "join",
            "keys",
            "kill",
            "last",
            "lc",
            "lcfirst",
            "length",
            "link",
            "listen",
            "local",
            "localtime",
            "log",
            "lstat",
            "lt",
            "ma",
            "map",
            "method",
            "mkdir",
            "msgctl",
            "msgget",
            "msgrcv",
            "msgsnd",
            "my",
            "ne",
            "next",
            "no",
            "not",
            "oct",
            "open",
            "opendir",
            "or",
            "ord",
            "our",
            "pack",
            "package",
            "pipe",
            "pop",
            "pos",
            "print",
            "printf",
            "prototype",
            "push",
            "q|0",
            "qq",
            "quotemeta",
            "qw",
            "qx",
            "rand",
            "read",
            "readdir",
            "readline",
            "readlink",
            "readpipe",
            "recv",
            "redo",
            "ref",
            "rename",
            "require",
            "reset",
            "return",
            "reverse",
            "rewinddir",
            "rindex",
            "rmdir",
            "say",
            "scalar",
            "seek",
            "seekdir",
            "select",
            "semctl",
            "semget",
            "semop",
            "send",
            "setgrent",
            "sethostent",
            "setnetent",
            "setpgrp",
            "setpriority",
            "setprotoent",
            "setpwent",
            "setservent",
            "setsockopt",
            "shift",
            "shmctl",
            "shmget",
            "shmread",
            "shmwrite",
            "shutdown",
            "sin",
            "sleep",
            "socket",
            "socketpair",
            "sort",
            "splice",
            "split",
            "sprintf",
            "sqrt",
            "srand",
            "stat",
            "state",
            "study",
            "sub",
            "substr",
            "symlink",
            "syscall",
            "sysopen",
            "sysread",
            "sysseek",
            "system",
            "syswrite",
            "tell",
            "telldir",
            "tie",
            "tied",
            "time",
            "times",
            "tr",
            "truncate",
            "uc",
            "ucfirst",
            "umask",
            "undef",
            "unless",
            "unlink",
            "unpack",
            "unshift",
            "untie",
            "until",
            "use",
            "utime",
            "values",
            "vec",
            "wait",
            "waitpid",
            "wantarray",
            "warn",
            "when",
            "while",
            "write",
            "x|0",
            "xor",
            "y|0",
        ]

        // https://perldoc.perl.org/perlre#Modifiers
        // aa and xx are valid, making max length 12
        let regexModifiers = "[dualxmsipngr]{0,12}"
        let perlKeywords = Keywords(
            pattern: #"[\w.]+"#,
            keyword: Keywords.Group(words: keywords)
        )
        let subst = Mode(
            scope: "subst",
            begin: #"[$@]\{"#,
            end: #"\}"#,
            keywords: perlKeywords
        )
        let method = Mode(
            begin: #"->\{"#,
            end: #"\}"#
            // contains defined later
        )
        let attr = Mode(
            scope: "attr",
            match: #"\s+:\s*\w+(\s*\(.*?\))?"#
        )
        let varMode = Mode(
            scope: "variable",
            contains: [attr],
            variants: [
                Mode(begin: #"\$\d"#),
                Mode(begin: .re(RegexSource.concat(
                    #"[$%@](?!")(\^\w\b|#\w+(::\w+)*|\{\w+\}|\w+(::\w*)*)"#,
                    // negative look-ahead tries to avoid matching patterns
                    // that are not Perl at all like $ident$, @ident@, etc.
                    "(?![A-Za-z])(?![@$%])"
                ))),
                // Only $= is a special Perl variable and one can't
                // declare @= or %=.
                Mode(begin: #"[$%@](?!")[^\s\w{=]|\$="#, relevance: 0),
            ]
        )
        let number = Mode(
            scope: "number",
            variants: [
                // decimal numbers:
                // include the case where a number starts with a dot (eg. .9),
                // and the leading 0? avoids mixing the first and second match
                // on 0.x cases
                Mode(match: #"0?\.[0-9][0-9_]+\b"#),
                // include the special versioned number (eg. v5.38)
                Mode(match: #"\bv?(0|[1-9][0-9_]*(\.[0-9_]+)?|[1-9][0-9_]*)\b"#),
                // non-decimal numbers:
                Mode(match: #"\b0[0-7][0-7_]*\b"#),
                Mode(match: #"\b0x[0-9a-fA-F][0-9a-fA-F_]*\b"#),
                Mode(match: #"\b0b[0-1][0-1_]*\b"#),
            ],
            relevance: 0
        )
        let stringContains = [
            CommonModes.backslashEscape,
            subst,
            varMode,
        ]
        let regexDelims = [
            "!",
            #"\/"#,
            #"\|"#,
            #"\?"#,
            "'",
            "\"", // valid but infrequent and weird
            "#", // valid but infrequent and weird
        ]
        func pairedDoubleRe(_ prefix: String, _ open: String, _ close: String = #"\1"#) -> String {
            let middle = (close == #"\1"#)
                ? close
                : RegexSource.concat(close, open)
            return RegexSource.concat(
                RegexSource.concat("(?:", prefix, ")"),
                open,
                #"(?:\\.|[^\\\/])*?"#,
                middle,
                #"(?:\\.|[^\\\/])*?"#,
                close,
                regexModifiers
            )
        }
        func pairedRe(_ prefix: String, _ open: String, _ close: String) -> String {
            RegexSource.concat(
                RegexSource.concat("(?:", prefix, ")"),
                open,
                #"(?:\\.|[^\\\/])*?"#,
                close,
                regexModifiers
            )
        }
        let titleMode = CommonModes.titleMode
        let perlDefaultContains: [Mode] = [
            varMode,
            CommonModes.hashCommentMode,
            CommonModes.comment(#"^=\w"#, "=cut") { m in
                m.endsWithParent = true
            },
            method,
            Mode(
                scope: "string",
                contains: stringContains,
                variants: [
                    Mode(begin: #"q[qwxr]?\s*\("#, end: #"\)"#, relevance: 5),
                    Mode(begin: #"q[qwxr]?\s*\["#, end: #"\]"#, relevance: 5),
                    Mode(begin: #"q[qwxr]?\s*\{"#, end: #"\}"#, relevance: 5),
                    Mode(begin: #"q[qwxr]?\s*\|"#, end: #"\|"#, relevance: 5),
                    Mode(begin: #"q[qwxr]?\s*<"#, end: ">", relevance: 5),
                    Mode(begin: #"qw\s+q"#, end: "q", relevance: 5),
                    Mode(begin: "'", end: "'", contains: [CommonModes.backslashEscape]),
                    Mode(begin: "\"", end: "\""),
                    Mode(begin: "`", end: "`", contains: [CommonModes.backslashEscape]),
                    Mode(begin: #"\{\w+\}"#, relevance: 0),
                    Mode(begin: #"-?\w+\s*=>"#, relevance: 0),
                ]
            ),
            number,
            // regexp container
            Mode(
                begin: .re(#"(\/\/|"# + CommonModes.reStartersRe + #"|\b(split|return|print|reverse|grep)\b)\s*"#),
                keywords: "split return print reverse grep",
                contains: [
                    CommonModes.hashCommentMode,
                    Mode(
                        scope: "regexp",
                        variants: [
                            // allow matching common delimiters
                            Mode(begin: .re(pairedDoubleRe("s|tr|y", RegexSource.either(regexDelims, capture: true)))),
                            // and then paired delmis
                            Mode(begin: .re(pairedDoubleRe("s|tr|y", #"\("#, #"\)"#))),
                            Mode(begin: .re(pairedDoubleRe("s|tr|y", #"\["#, #"\]"#))),
                            Mode(begin: .re(pairedDoubleRe("s|tr|y", #"\{"#, #"\}"#))),
                        ],
                        relevance: 2
                    ),
                    Mode(
                        scope: "regexp",
                        variants: [
                            // could be a comment in many languages so do not
                            // count as relevant
                            Mode(begin: #"(m|qr)\/\/"#, relevance: 0),
                            // prefix is optional with /regex/
                            Mode(begin: .re(pairedRe("(?:m|qr)?", #"\/"#, #"\/"#))),
                            // allow matching common delimiters
                            Mode(begin: .re(pairedRe("m|qr", RegexSource.either(regexDelims, capture: true), #"\1"#))),
                            // allow common paired delmins
                            Mode(begin: .re(pairedRe("m|qr", #"\("#, #"\)"#))),
                            Mode(begin: .re(pairedRe("m|qr", #"\["#, #"\]"#))),
                            Mode(begin: .re(pairedRe("m|qr", #"\{"#, #"\}"#))),
                        ]
                    ),
                ],
                relevance: 0
            ),
            Mode(
                scope: "function",
                beginKeywords: "sub method",
                end: #"(\s*\(.*?\))?[;{]"#,
                contains: [titleMode, attr],
                relevance: 5,
                excludeEnd: true
            ),
            Mode(
                scope: "class",
                beginKeywords: "class",
                end: "[;{]",
                contains: [titleMode, attr, number],
                relevance: 5,
                excludeEnd: true
            ),
            Mode(begin: #"-\w\b"#, relevance: 0),
            Mode(
                begin: "^__DATA__$",
                end: "^__END__$",
                contains: [
                    Mode(scope: "comment", begin: "^@@.*", end: "$"),
                ],
                subLanguage: ["mojolicious"]
            ),
        ]
        subst.contains = perlDefaultContains
        method.contains = perlDefaultContains

        return LanguageDefinition(
            name: "perl",
            aliases: ["pl", "pm"],
            root: Mode(
                keywords: perlKeywords,
                contains: perlDefaultContains
            )
        )
    }
}
