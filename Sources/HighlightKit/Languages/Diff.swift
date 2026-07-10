import Foundation

extension LanguageCatalog {
    /// Diff. Port of highlight.js `languages/diff.js`.
    public static let diff = LanguageDescriptor(name: "diff", aliases: ["patch"]) {
        LanguageDefinition(
            name: "diff",
            aliases: ["patch"],
            root: Mode(
                contains: [
                    Mode(
                        scope: "meta",
                        match: .re(RegexSource.either(
                            #"^@@ +-\d+,\d+ +\+\d+,\d+ +@@"#, // @@ -1,2 +1,2 @@
                            #"^\*\*\* +\d+,\d+ +\*\*\*\*$"#,
                            #"^--- +\d+,\d+ +----$"#
                        )),
                        relevance: 10
                    ),
                    Mode(
                        scope: "comment",
                        variants: [
                            Mode(
                                begin: .re(RegexSource.either(
                                    "Index: ",
                                    "^index",
                                    "={3,}",
                                    "^-{3}",
                                    #"^\*{3} "#,
                                    #"^\+{3}"#,
                                    "^diff --git"
                                )),
                                end: "$"
                            ),
                            Mode(match: #"^\*{15}$"#),
                        ]
                    ),
                    Mode(
                        scope: "addition",
                        begin: #"^\+"#,
                        end: "$"
                    ),
                    Mode(
                        scope: "deletion",
                        begin: "^-",
                        end: "$"
                    ),
                    Mode(
                        scope: "addition",
                        begin: "^!",
                        end: "$"
                    ),
                ]
            )
        )
    }
}
