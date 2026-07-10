import Foundation

extension LanguageCatalog {
    /// Plain text — no highlighting.
    public static let plaintext = LanguageDescriptor(name: "plaintext", aliases: ["text", "txt"]) {
        LanguageDefinition(
            name: "plaintext",
            aliases: ["text", "txt"],
            disableAutodetect: true,
            root: Mode()
        )
    }
}
