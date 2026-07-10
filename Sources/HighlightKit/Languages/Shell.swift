import Foundation

extension LanguageCatalog {
    /// Shell Session. Port of highlight.js `languages/shell.js`.
    public static let shell = LanguageDescriptor(name: "shell", aliases: ["console", "shellsession"]) {
        LanguageDefinition(
            name: "shell",
            aliases: ["console", "shellsession"],
            root: Mode(
                contains: [
                    Mode(
                        scope: "meta.prompt",
                        // We cannot add \s (spaces) in the regular expression
                        // otherwise it will be too broad and produce unexpected
                        // result. For instance, in the following example, it
                        // would match "echo /path/to/home >" as a prompt:
                        // echo /path/to/home > t.exe
                        // (`[` escaped inside the class for ICU)
                        begin: #"^\s{0,3}[/~\w\d\[\]()@-]*[>%$#][ ]?"#,
                        starts: Mode(
                            end: #"[^\\](?=\s*$)"#,
                            subLanguage: ["bash"]
                        )
                    ),
                ]
            )
        )
    }
}
