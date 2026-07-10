import Foundation

extension LanguageCatalog {
    /// Makefile. Port of highlight.js `languages/makefile.js`.
    public static let makefile = LanguageDescriptor(name: "makefile", aliases: ["mk", "mak", "make"]) {
        /* Variables: simple (eg $(var)) and special (eg $@) */
        let variable = Mode(
            scope: "variable",
            variants: [
                Mode(
                    begin: .re(#"\$\("# + CommonModes.underscoreIdentRe + #"\)"#),
                    contains: [CommonModes.backslashEscape]
                ),
                Mode(begin: #"\$[@%<?\^\+\*]"#),
            ]
        )
        /* Quoted string with variables inside */
        let quoteString = Mode(
            scope: "string",
            begin: "\"",
            end: "\"",
            contains: [
                CommonModes.backslashEscape,
                variable,
            ]
        )
        /* Function: $(func arg,...) */
        let funcMode = Mode(
            scope: "variable",
            begin: #"\$\([\w-]+\s"#,
            end: #"\)"#,
            keywords: [
                "built_in": Keywords.Group(stringLiteral:
                    "subst patsubst strip findstring filter filter-out sort "
                    + "word wordlist firstword lastword dir notdir suffix basename "
                    + "addsuffix addprefix join wildcard realpath abspath error warning "
                    + "shell origin flavor foreach if or and call eval file value"),
            ],
            contains: [
                variable,
                quoteString, // Added QUOTE_STRING as they can be a part of functions
            ]
        )
        /* Variable assignment */
        let assignment = Mode(begin: .re("^" + CommonModes.underscoreIdentRe + #"\s*(?=[:+?]?=)"#))
        /* Meta targets (.PHONY) */
        let meta = Mode(
            scope: "meta",
            begin: #"^\.PHONY:"#,
            end: "$",
            keywords: Keywords(
                pattern: #"[\.\w]+"#,
                ["keyword": ".PHONY"]
            )
        )
        /* Targets */
        let target = Mode(
            scope: "section",
            begin: #"^[^\s]+:"#,
            end: "$",
            contains: [variable]
        )

        return LanguageDefinition(
            name: "makefile",
            aliases: ["mk", "mak", "make"],
            root: Mode(
                keywords: Keywords(
                    pattern: #"[\w-]+"#,
                    [
                        "keyword": Keywords.Group(stringLiteral:
                            "define endef undefine ifdef ifndef ifeq ifneq else endif "
                            + "include -include sinclude override export unexport private vpath"),
                    ]
                ),
                contains: [
                    CommonModes.hashCommentMode,
                    variable,
                    quoteString,
                    funcMode,
                    assignment,
                    meta,
                    target,
                ]
            )
        )
    }
}
