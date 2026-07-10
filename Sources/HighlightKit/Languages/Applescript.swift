import Foundation

extension LanguageCatalog {
    /// AppleScript. Port of highlight.js `languages/applescript.js`.
    public static let applescript = LanguageDescriptor(name: "applescript", aliases: ["osascript"]) {
        let string: Mode = {
            let m = CommonModes.quoteStringMode
            m.illegal = nil
            return m
        }()
        let params = Mode(
            scope: "params",
            begin: #"\("#,
            end: #"\)"#,
            contains: [
                Mode.selfReference,
                CommonModes.cNumberMode,
                string,
            ]
        )
        let commentMode1 = CommonModes.comment("--", "$")
        let commentMode2 = CommonModes.comment(#"\(\*"#, #"\*\)"#) { mode in
            mode.contains = [
                Mode.selfReference, // allow nesting
                commentMode1,
            ]
        }
        let comments = [
            commentMode1,
            commentMode2,
            CommonModes.hashCommentMode,
        ]

        let keywordPatterns = [
            #"apart from"#,
            #"aside from"#,
            #"instead of"#,
            #"out of"#,
            #"greater than"#,
            #"isn't|(doesn't|does not) (equal|come before|come after|contain)"#,
            #"(greater|less) than( or equal)?"#,
            #"(starts?|ends|begins?) with"#,
            #"contained by"#,
            #"comes (before|after)"#,
            #"a (ref|reference)"#,
            #"POSIX (file|path)"#,
            #"(date|time) string"#,
            #"quoted form"#,
        ]

        let builtInPatterns = [
            #"clipboard info"#,
            #"the clipboard"#,
            #"info for"#,
            #"list (disks|folder)"#,
            #"mount volume"#,
            #"path to"#,
            #"(close|open for) access"#,
            #"(get|set) eof"#,
            #"current date"#,
            #"do shell script"#,
            #"get volume settings"#,
            #"random number"#,
            #"set volume"#,
            #"system attribute"#,
            #"system info"#,
            #"time to GMT"#,
            #"(load|run|store) script"#,
            #"scripting components"#,
            #"ASCII (character|number)"#,
            #"localized string"#,
            #"choose (application|color|file|file name|folder|from list|remote application|URL)"#,
            #"display (alert|dialog)"#,
        ]

        return LanguageDefinition(
            name: "applescript",
            aliases: ["osascript"],
            root: Mode(
                keywords: [
                    "keyword": Keywords.Group(stringLiteral:
                        "about above after against and around as at back before beginning "
                        + "behind below beneath beside between but by considering "
                        + "contain contains continue copy div does eighth else end equal "
                        + "equals error every exit fifth first for fourth from front "
                        + "get given global if ignoring in into is it its last local me "
                        + "middle mod my ninth not of on onto or over prop property put ref "
                        + "reference repeat returning script second set seventh since "
                        + "sixth some tell tenth that the|0 then third through thru "
                        + "timeout times to transaction try until where while whose with "
                        + "without"
                    ),
                    "literal":
                        "AppleScript false linefeed return pi quote result space tab true",
                    "built_in": Keywords.Group(stringLiteral:
                        "alias application boolean class constant date file integer list "
                        + "number real record string text "
                        + "activate beep count delay launch log offset read round "
                        + "run say summarize write "
                        + "character characters contents day frontmost id item length "
                        + "month name|0 paragraph paragraphs rest reverse running time version "
                        + "weekday word words year"
                    ),
                ],
                illegal: [#"\/\/|->|=>|\[\["#],
                contains: [
                    string,
                    CommonModes.cNumberMode,
                    Mode(
                        scope: "built_in",
                        begin: .re(RegexSource.concat(
                            #"\b"#,
                            RegexSource.either(builtInPatterns),
                            #"\b"#
                        ))
                    ),
                    Mode(
                        scope: "built_in",
                        begin: #"^\s*return\b"#
                    ),
                    Mode(
                        scope: "literal",
                        begin: #"\b(text item delimiters|current application|missing value)\b"#
                    ),
                    Mode(
                        scope: "keyword",
                        begin: .re(RegexSource.concat(
                            #"\b"#,
                            RegexSource.either(keywordPatterns),
                            #"\b"#
                        ))
                    ),
                    Mode(
                        beginKeywords: "on",
                        illegal: [#"[${=;\n]"#],
                        contains: [
                            CommonModes.underscoreTitleMode,
                            params,
                        ]
                    ),
                ] + comments
            )
        )
    }
}
