import Dispatch
import Foundation
import Synchronization
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
        let (starts, startsContinuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let matchCount = Mutex(0)
        let resume = DispatchSemaphore(value: 0)
        let descriptor = LanguageDescriptor(name: "cancellable") {
            LanguageDefinition(
                name: "cancellable",
                root: Mode(contains: [
                    Mode(begin: "x", onBegin: { _, _ in
                        let first = matchCount.withLock { count in
                            count += 1
                            return count == 1
                        }
                        if first {
                            startsContinuation.yield()
                            resume.wait()
                        }
                    })
                ])
            )
        }
        let highlighter = Highlighter(languages: [descriptor])
        let task = Task {
            try await highlighter.highlight(
                "x",
                selection: .named("cancellable")
            )
        }

        var iterator = starts.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        resume.signal()
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        startsContinuation.finish()
    }
}
