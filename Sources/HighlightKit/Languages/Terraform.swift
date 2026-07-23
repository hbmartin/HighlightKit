import Foundation

extension LanguageCatalog {
    /// Terraform/HCL. Port of highlightjs-terraform at eb1b966.
    public static let terraform = LanguageDescriptor(
        name: "terraform",
        aliases: ["tf", "hcl"]
    ) {
        func quotedString(contains: [Mode]? = nil) -> Mode {
            Mode(scope: "string", begin: #"""#, end: #"""#, contains: contains)
        }
        let number = Mode(scope: "number", begin: #"\b\d+(\.\d+)?"#, relevance: 0)
        let deepestVariable = Mode(scope: "variable", begin: #"\$\{"#, end: #"\}"#)
        let nestedString = quotedString(contains: [
            Mode(
                scope: "variable",
                begin: #"\$\{"#,
                end: #"\}"#,
                contains: [
                    quotedString(contains: [deepestVariable]),
                    Mode(scope: "meta", begin: #"[A-Za-z_0-9]*\("#, end: #"\)"#),
                ]
            ),
        ])
        let function = Mode(
            scope: "meta",
            begin: #"[A-Za-z_0-9]*\("#,
            end: #"\)"#,
            contains: [number, nestedString, Mode.selfReference]
        )
        let interpolation = Mode(
            scope: "variable",
            begin: #"\$\{"#,
            end: #"\}"#,
            contains: [quotedString(), function],
            relevance: 9
        )
        let string = quotedString(contains: [interpolation])
        return LanguageDefinition(
            name: "terraform",
            aliases: ["tf", "hcl"],
            root: Mode(
                keywords: "resource variable provider output locals module data terraform|10",
                contains: [
                    CommonModes.comment("\\#", "$"),
                    number,
                    string,
                ]
            )
        )
    }
}
