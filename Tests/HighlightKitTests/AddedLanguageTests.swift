import Testing
@testable import HighlightKit

@Suite("Added language grammars")
struct AddedLanguageTests {
    @Test func terraformHighlightsBlocksInterpolationAndFunctions() throws {
        let code = #"resource "demo" "main" { value = "${merge(local.tags)}" }"#
        let result = try LanguageRegistry(languages: [LanguageCatalog.terraform]).highlight(
            code,
            languageName: "hcl",
            ignoreIllegals: true,
            continuation: nil
        )
        #expect(result.language == "terraform")
        #expect(result.tokens.contains { $0.scope == "keyword" })
        #expect(result.tokens.contains { $0.scope == "variable" })
        #expect(result.tokens.contains { $0.scope == "meta" })
    }

    @Test func protobufHighlightsMessagesTypesAndRPCs() throws {
        let code = "message User { string name = 1; } service API { rpc Get(User) returns (User); }"
        let result = try LanguageRegistry(languages: [LanguageCatalog.protobuf]).highlight(
            code,
            languageName: "proto",
            ignoreIllegals: true,
            continuation: nil
        )
        #expect(result.language == "protobuf")
        #expect(result.tokens.contains { $0.scope == "title.class" })
        #expect(result.tokens.contains { $0.scope == "type" })
        #expect(result.tokens.contains { $0.scope == "function" })
    }

    @Test func graphqlHighlightsOperationsVariablesAndFields() throws {
        let code = "query User($id: ID!) { user(id: $id) { name ...Details } }"
        let result = try LanguageRegistry(languages: [LanguageCatalog.graphql]).highlight(
            code,
            languageName: "gql",
            ignoreIllegals: true,
            continuation: nil
        )
        #expect(result.language == "graphql")
        #expect(result.tokens.contains { $0.scope == "variable" })
        #expect(result.tokens.contains { $0.scope == "punctuation" })
        #expect(result.tokens.contains { $0.scope == "symbol" })
    }

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
