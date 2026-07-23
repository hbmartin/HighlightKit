import Testing
@testable import HighlightKit

@Suite("Added language grammars")
struct AddedLanguageTests {
    @Test func elixirHighlightsDeclarationsSigilsAndAtoms() throws {
        let code = #"defmodule Demo do\n  def greet(name), do: ~r/hello #{name}/u\n  :ok\nend"#
        let result = try LanguageRegistry(languages: [LanguageCatalog.elixir]).highlight(
            code,
            languageName: "ex",
            ignoreIllegals: true,
            continuation: nil
        )
        #expect(result.language == "elixir")
        #expect(result.tokens.contains { $0.scope == "title" })
        #expect(result.tokens.contains { $0.scope == "regex" })
        #expect(result.tokens.contains { $0.scope == "symbol" })
    }
}
