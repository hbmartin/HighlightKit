import Foundation

extension LanguageCatalog {
    /// PowerShell. Port of highlight.js `languages/powershell.js`.
    public static let powershell = LanguageDescriptor(name: "powershell", aliases: ["pwsh", "ps", "ps1"]) {
        let types = [
            "string",
            "char",
            "byte",
            "int",
            "long",
            "bool",
            "decimal",
            "single",
            "double",
            "DateTime",
            "xml",
            "array",
            "hashtable",
            "void",
        ]

        // https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/approved-verbs-for-windows-powershell-commands
        let validVerbs =
            "Add|Clear|Close|Copy|Enter|Exit|Find|Format|Get|Hide|Join|Lock|"
            + "Move|New|Open|Optimize|Pop|Push|Redo|Remove|Rename|Reset|Resize|"
            + "Search|Select|Set|Show|Skip|Split|Step|Switch|Undo|Unlock|"
            + "Watch|Backup|Checkpoint|Compare|Compress|Convert|ConvertFrom|"
            + "ConvertTo|Dismount|Edit|Expand|Export|Group|Import|Initialize|"
            + "Limit|Merge|Mount|Out|Publish|Restore|Save|Sync|Unpublish|Update|"
            + "Approve|Assert|Build|Complete|Confirm|Deny|Deploy|Disable|Enable|Install|Invoke|"
            + "Register|Request|Restart|Resume|Start|Stop|Submit|Suspend|Uninstall|"
            + "Unregister|Wait|Debug|Measure|Ping|Repair|Resolve|Test|Trace|Connect|"
            + "Disconnect|Read|Receive|Send|Write|Block|Grant|Protect|Revoke|Unblock|"
            + "Unprotect|Use|ForEach|Sort|Tee|Where"

        let comparisonOperators =
            "-and|-as|-band|-bnot|-bor|-bxor|-casesensitive|-ccontains|-ceq|-cge|-cgt|"
            + "-cle|-clike|-clt|-cmatch|-cne|-cnotcontains|-cnotlike|-cnotmatch|-contains|"
            + "-creplace|-csplit|-eq|-exact|-f|-file|-ge|-gt|-icontains|-ieq|-ige|-igt|"
            + "-ile|-ilike|-ilt|-imatch|-in|-ine|-inotcontains|-inotlike|-inotmatch|"
            + "-ireplace|-is|-isnot|-isplit|-join|-le|-like|-lt|-match|-ne|-not|"
            + "-notcontains|-notin|-notlike|-notmatch|-or|-regex|-replace|-shl|-shr|"
            + "-split|-wildcard|-xor"

        let keywordWords =
            "if else foreach return do while until elseif begin for trap data dynamicparam "
            + "end break throw param continue finally in switch exit filter try process catch "
            + "hidden static parameter"

        let keywords = Keywords(
            pattern: #"-?[A-z\.\-]+\b"#,
            [
                "keyword": Keywords.Group(stringLiteral: keywordWords),
                // "echo" relevance has been set to 0 to avoid auto-detect conflicts with shell transcripts
                "built_in": Keywords.Group(stringLiteral:
                    "ac asnp cat cd CFS chdir clc clear clhy cli clp cls clv cnsn compare copy cp "
                    + "cpi cpp curl cvpa dbp del diff dir dnsn ebp echo|0 epal epcsv epsn erase etsn exsn fc fhx "
                    + "fl ft fw gal gbp gc gcb gci gcm gcs gdr gerr ghy gi gin gjb gl gm gmo gp gps gpv group "
                    + "gsn gsnp gsv gtz gu gv gwmi h history icm iex ihy ii ipal ipcsv ipmo ipsn irm ise iwmi "
                    + "iwr kill lp ls man md measure mi mount move mp mv nal ndr ni nmo npssc nsn nv ogv oh "
                    + "popd ps pushd pwd r rbp rcjb rcsn rd rdr ren ri rjb rm rmdir rmo rni rnp rp rsn rsnp "
                    + "rujb rv rvpa rwmi sajb sal saps sasv sbp sc scb select set shcm si sl sleep sls sort sp "
                    + "spjb spps spsv start stz sujb sv swmi tee trcm type wget where wjb write"
                ),
            ]
        )

        let titleNameRe = #"\w[\w\d]*((-)[\w\d]+)*"#

        let backtickEscape = Mode(
            begin: #"`[\s\S]"#,
            relevance: 0
        )

        let varMode = Mode(
            scope: "variable",
            variants: [
                Mode(begin: #"\$\B"#),
                Mode(scope: "keyword", begin: #"\$this"#),
                Mode(begin: #"\$[\w\d][\w\d_:]*"#),
            ]
        )

        let literal = Mode(
            scope: "literal",
            begin: #"\$(null|true|false)\b"#
        )

        let quoteString = Mode(
            scope: "string",
            contains: [
                backtickEscape,
                varMode,
                Mode(
                    scope: "variable",
                    begin: #"\$[A-z]"#,
                    end: "[^A-z]"
                ),
            ],
            variants: [
                Mode(begin: "\"", end: "\""),
                Mode(begin: "@\"", end: "^\"@"),
            ]
        )

        let aposString = Mode(
            scope: "string",
            variants: [
                Mode(begin: "'", end: "'"),
                Mode(begin: "@'", end: "^'@"),
            ]
        )

        let psHelptags = Mode(
            scope: "doctag",
            variants: [
                /* no paramater help tags */
                Mode(begin: #"\.(synopsis|description|example|inputs|outputs|notes|link|component|role|functionality)"#),
                /* one parameter help tags */
                Mode(begin: #"\.(parameter|forwardhelptargetname|forwardhelpcategory|remotehelprunspace|externalhelp)\s+\S+"#),
            ]
        )

        // Upstream builds this as `hljs.inherit(hljs.COMMENT(null, null), {...})`,
        // where the override *replaces* `contains` — so no doctag/english-words
        // children survive; only PS_HELPTAGS.
        let psComment = Mode(
            scope: "comment",
            contains: [psHelptags],
            variants: [
                /* single-line comment */
                Mode(begin: "#", end: "$"),
                /* multi-line comment */
                Mode(begin: "<#", end: "#>"),
            ]
        )

        let cmdlets = Mode(
            scope: "built_in",
            variants: [
                Mode(begin: .re("(" + validVerbs + ")+(-)[\\w\\d]+")),
            ]
        )

        let psClass = Mode(
            scope: "class",
            beginKeywords: "class enum",
            end: #"\s*[{]"#,
            contains: [CommonModes.titleMode],
            relevance: 0,
            excludeEnd: true
        )

        let psFunction = Mode(
            scope: "function",
            begin: #"function\s+"#,
            end: #"\s*\{|$"#,
            contains: [
                Mode(
                    scope: "keyword",
                    begin: "function",
                    relevance: 0
                ),
                Mode(
                    scope: "title",
                    begin: .re(titleNameRe),
                    relevance: 0
                ),
                Mode(
                    scope: "params",
                    begin: #"\("#,
                    end: #"\)"#,
                    contains: [varMode],
                    relevance: 0
                ),
                // CMDLETS
            ],
            relevance: 0,
            excludeEnd: true,
            returnBegin: true
        )

        // Using statment, plus type, plus assembly name.
        let psUsing = Mode(
            begin: #"using\s"#,
            end: "$",
            contains: [
                quoteString,
                aposString,
                Mode(
                    scope: "keyword",
                    begin: "(using|assembly|command|module|namespace|type)"
                ),
            ],
            returnBegin: true
        )

        // Comperison operators & function named parameters.
        let psArguments = Mode(
            variants: [
                // PS literals are pretty verbose so it's a good idea to accent them a bit.
                Mode(
                    scope: "operator",
                    begin: .re("(" + comparisonOperators + ")\\b")
                ),
                Mode(
                    scope: "literal",
                    begin: #"(-){1,2}[\w\d-]+"#,
                    relevance: 0
                ),
            ]
        )

        let hashSigns = Mode(
            scope: "selector-tag",
            begin: #"@\B"#,
            relevance: 0
        )

        // It's a very general rule so I'll narrow it a bit with some strict boundaries
        // to avoid any possible false-positive collisions!
        let psMethods = Mode(
            scope: "function",
            begin: #"\[.*\]\s*[\w]+[ ]??\("#,
            end: "$",
            contains: [
                Mode(
                    scope: "keyword",
                    begin: .re("(" + keywordWords.split(separator: " ").joined(separator: "|") + ")\\b"),
                    relevance: 0,
                    endsParent: true
                ),
                { let m = CommonModes.titleMode; m.endsParent = true; return m }(),
            ],
            relevance: 0,
            returnBegin: true
        )

        let gentlemansSet: [Mode] = [
            // STATIC_MEMBER,
            psMethods,
            psComment,
            backtickEscape,
            CommonModes.numberMode,
            quoteString,
            aposString,
            // PS_NEW_OBJECT_TYPE,
            cmdlets,
            varMode,
            literal,
            hashSigns,
        ]

        let psType = Mode(
            begin: #"\["#,
            end: #"\]"#,
            contains: [Mode.selfReference]
                + gentlemansSet
                + [
                    Mode(
                        scope: "built_in",
                        begin: .re("(" + types.joined(separator: "|") + ")"),
                        relevance: 0
                    ),
                    Mode(
                        scope: "type",
                        begin: #"[\.\w\d]+"#,
                        relevance: 0
                    ),
                ],
            relevance: 0,
            excludeBegin: true,
            excludeEnd: true
        )

        psMethods.contains?.insert(psType, at: 0)

        return LanguageDefinition(
            name: "powershell",
            aliases: ["pwsh", "ps", "ps1"],
            caseInsensitive: true,
            root: Mode(
                keywords: keywords,
                contains: gentlemansSet + [
                    psClass,
                    psFunction,
                    psUsing,
                    psArguments,
                    psType,
                ]
            )
        )
    }
}
