import Foundation

extension LanguageCatalog {
    /// YAML. Port of highlight.js `languages/yaml.js`.
    public static let yaml = LanguageDescriptor(name: "yaml", aliases: ["yml"]) {
        let literals = "true false yes no null"

        // YAML spec allows non-reserved URI characters in tags.
        // (ICU: the bare `[` inside the JS character class must be escaped.)
        let uriCharacters = #"[\w#;/?:@&=+$,.~*'()\[\]]+"#

        // Define keys as starting with a word character
        // ...containing word chars, spaces, colons, forward-slashes, hyphens and periods
        // ...and ending with a colon followed immediately by a space, tab or newline.
        // The YAML spec allows for much more than this, but this covers most use-cases.
        let key = Mode(
            scope: "attr",
            variants: [
                // added brackets support and special char support
                Mode(begin: #"[\w*@][\w*@ :()\./-]*:(?=[ \t]|$)"#),
                // double quoted keys - with brackets and special char support
                Mode(begin: #""[\w*@][\w*@ :()\./-]*":(?=[ \t]|$)"#),
                // single quoted keys - with brackets and special char support
                Mode(begin: #"'[\w*@][\w*@ :()\./-]*':(?=[ \t]|$)"#),
            ]
        )

        let templateVariables = Mode(
            scope: "template-variable",
            variants: [
                // jinja templates Ansible
                Mode(begin: #"\{\{"#, end: #"\}\}"#),
                // Ruby i18n
                Mode(begin: #"%\{"#, end: #"\}"#),
            ]
        )

        let singleQuoteString = Mode(
            scope: "string",
            begin: "'",
            end: "'",
            contains: [
                Mode(scope: "char.escape", match: "''", relevance: 0),
            ],
            relevance: 0
        )

        let string = Mode(
            scope: "string",
            contains: [
                CommonModes.backslashEscape,
                templateVariables,
            ],
            variants: [
                Mode(begin: "\"", end: "\""),
                Mode(begin: #"\S+"#),
            ],
            relevance: 0
        )

        // Strings inside of value containers (objects) can't contain braces,
        // brackets, or commas
        let containerString = string.copied { m in
            m.variants = [
                Mode(begin: "'", end: "'", contains: [
                    Mode(begin: "''", relevance: 0),
                ]),
                Mode(begin: "\"", end: "\""),
                Mode(begin: #"[^\s,{}\[\]]+"#),
            ]
        }

        let dateRe = "[0-9]{4}(-[0-9][0-9]){0,2}"
        let timeRe = "([Tt \\t][0-9][0-9]?(:[0-9][0-9]){2})?"
        let fractionRe = "(\\.[0-9]*)?"
        let zoneRe = "([ \\t])*(Z|[-+][0-9][0-9]?(:[0-9][0-9])?)?"
        let timestamp = Mode(
            scope: "number",
            begin: .re("\\b" + dateRe + timeRe + fractionRe + zoneRe + "\\b")
        )

        let valueContainer = Mode(
            end: ",",
            keywords: Keywords(stringLiteral: literals),
            relevance: 0,
            excludeEnd: true,
            endsWithParent: true
        )
        let object = Mode(
            begin: #"\{"#,
            end: #"\}"#,
            illegal: ["\\n"],
            contains: [valueContainer],
            relevance: 0
        )
        let array = Mode(
            begin: "\\[",
            end: "\\]",
            illegal: ["\\n"],
            contains: [valueContainer],
            relevance: 0
        )

        let modes: [Mode] = [
            key,
            Mode(
                scope: "meta",
                begin: "^---\\s*$",
                relevance: 10
            ),
            // multi line string
            // Blocks start with a | or > followed by a newline
            //
            // Indentation of subsequent lines must be the same to
            // be considered part of the block
            Mode(
                scope: "string",
                begin: "[\\|>]([1-9]?[+-])?[ ]*\\n( +)[^ ][^\\n]*\\n(\\2[^\\n]+\\n?)*"
            ),
            // Ruby/Rails erb
            Mode(
                begin: "<%[%=-]?",
                end: "[%-]?%>",
                subLanguage: ["ruby"],
                relevance: 0,
                excludeBegin: true,
                excludeEnd: true
            ),
            // named tags
            Mode(
                scope: "type",
                begin: .re("!\\w+!" + uriCharacters)
            ),
            // https://yaml.org/spec/1.2/spec.html#id2784064
            // verbatim tags
            Mode(
                scope: "type",
                begin: .re("!<" + uriCharacters + ">")
            ),
            // primary tags
            Mode(
                scope: "type",
                begin: .re("!" + uriCharacters)
            ),
            // secondary tags
            Mode(
                scope: "type",
                begin: .re("!!" + uriCharacters)
            ),
            // fragment id &ref
            Mode(
                scope: "meta",
                begin: .re("&" + CommonModes.underscoreIdentRe + "$")
            ),
            // fragment reference *ref
            Mode(
                scope: "meta",
                begin: .re("\\*" + CommonModes.underscoreIdentRe + "$")
            ),
            // array listing
            Mode(
                scope: "bullet",
                // TODO: remove |$ hack when we have proper look-ahead support
                begin: "-(?=[ ]|$)",
                relevance: 0
            ),
            CommonModes.hashCommentMode,
            Mode(
                beginKeywords: literals,
                keywords: Keywords(["literal": Keywords.Group(stringLiteral: literals)])
            ),
            timestamp,
            // numbers are any valid C-style number that
            // sit isolated from other words
            Mode(
                scope: "number",
                begin: .re(CommonModes.cNumberRe + "\\b"),
                relevance: 0
            ),
            object,
            array,
            singleQuoteString,
            string,
        ]

        var valueModes = modes
        valueModes.removeLast()
        valueModes.append(containerString)
        valueContainer.contains = valueModes

        return LanguageDefinition(
            name: "yaml",
            aliases: ["yml"],
            caseInsensitive: true,
            root: Mode(contains: modes)
        )
    }
}
