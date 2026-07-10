import Foundation

extension LanguageCatalog {
    /// Dockerfile. Port of highlight.js `languages/dockerfile.js`.
    public static let dockerfile = LanguageDescriptor(name: "dockerfile", aliases: ["docker"]) {
        let keywords = [
            "from",
            "maintainer",
            "expose",
            "env",
            "arg",
            "user",
            "onbuild",
            "stopsignal",
        ]
        return LanguageDefinition(
            name: "dockerfile",
            aliases: ["docker"],
            caseInsensitive: true,
            root: Mode(
                keywords: Keywords(keyword: Keywords.Group(words: keywords)),
                illegal: ["</"],
                contains: [
                    CommonModes.hashCommentMode,
                    CommonModes.aposStringMode,
                    CommonModes.quoteStringMode,
                    CommonModes.numberMode,
                    Mode(
                        beginKeywords: "run cmd entrypoint volume add copy workdir label healthcheck shell",
                        starts: Mode(
                            end: #"[^\\]$"#,
                            subLanguage: ["bash"]
                        )
                    ),
                ]
            )
        )
    }
}
