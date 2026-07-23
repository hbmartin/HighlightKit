import Foundation
import Testing
@testable import HighlightKit

@Suite("Strict public highlighting API")
struct StrictAPITests {
    @Test func namedAliasesCanonicalizeAndUnknownLanguagesThrow() throws {
        let highlighter = Highlighter(languages: [LanguageCatalog.ruby])
        let result = try highlighter.highlight("puts :ok", selection: .named("rb"))
        #expect(result.language == "ruby")
        #expect(throws: HighlightError.self) {
            try highlighter.highlight("text", selection: .named("missing"))
        }
    }

    @Test func plainIsIntentionalAndCarriesUTF16Length() throws {
        let result = try Highlighter.shared.highlight("a😀", selection: .plain)
        #expect(result.language == nil)
        #expect(result.tokens.isEmpty)
        #expect(result.sourceLength == 3)
    }

    @Test func tokenBudgetKeepsExactParserState() throws {
        let highlighter = Highlighter(languages: [LanguageCatalog.swift])
        let code = "let value = 42 // comment\nreturn value"
        let full = try highlighter.highlight(code, selection: .named("swift"))
        let limited = try highlighter.highlight(
            code,
            selection: .named("swift"),
            budget: HighlightBudget(maximumTokens: 1)
        )
        #expect(limited.tokens.count == min(1, full.tokens.count))
        #expect(limited.omittedTokenCount == max(0, full.tokens.count - 1))
        #expect(limited.isTruncated == (full.tokens.count > 1))
        #expect(limited.relevance == full.relevance)
        #expect(limited.continuation == full.continuation)
        #expect(limited.sourceLength == code.utf16.count)
    }

    @Test func asyncNamedCancellationThrows() async {
        let task = Task {
            try await Highlighter.shared.highlight(
                String(repeating: "let value = 42\n", count: 20_000),
                selection: .named("swift")
            )
        }
        task.cancel()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}
