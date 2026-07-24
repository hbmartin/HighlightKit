import Dispatch
import Foundation
import Synchronization
import Testing
@testable import HighlightKit

@Suite("Incremental highlighted document")
struct HighlightedDocumentTests {
    @Test func preservesLineTerminatorsAndProducesRangeSnapshots() async throws {
        let text = "let a = 1\r\nlet b = 2\rlet c = 3\n"
        let document = try await HighlightedDocument(
            text: text,
            selection: .named("swift"),
            checkpointInterval: 2
        )
        #expect(await document.text == text)
        #expect(await document.lineCount == 4)

        let source = text as NSString
        let selected = source.range(of: "let b = 2")
        let snapshot = try await document.snapshot(in: selected)
        #expect(snapshot.text == "let b = 2")
        #expect(snapshot.sourceRange == selected)
        #expect(snapshot.tokens.allSatisfy { NSMaxRange($0.range) <= selected.length })
        #expect(snapshot.tokens.contains { $0.range.location == 0 && $0.scope == "keyword" })
    }

    @Test func singleAndMultilineEditsUpdateTextAndTokens() async throws {
        let document = try await HighlightedDocument(
            text: "let first = 1\nlet second = 2\n",
            selection: .named("swift"),
            checkpointInterval: 1
        )
        let original = await document.text as NSString
        _ = try await document.replaceCharacters(
            in: original.range(of: "first"),
            with: "renamed"
        )
        var updated = await document.text
        #expect(updated == "let renamed = 1\nlet second = 2\n")

        let insertion = (updated as NSString).range(of: "let second")
        _ = try await document.replaceCharacters(
            in: insertion,
            with: "// inserted\nlet second"
        )
        updated = await document.text
        #expect(updated.contains("// inserted\nlet second"))
        let snapshot = try await document.snapshot()
        #expect(snapshot.tokens.contains { $0.scope == "comment" })

        let insertedLine = (updated as NSString).range(of: "// inserted\n")
        _ = try await document.replaceCharacters(in: insertedLine, with: "")
        #expect(await document.text == "let renamed = 1\nlet second = 2\n")
    }

    @Test func unicodeRangesAreUTF16AndInvalidBoundariesAreRejected() async throws {
        let document = try await HighlightedDocument(
            text: "let value = \"😀\"\n",
            selection: .named("swift")
        )
        let source = await document.text as NSString
        let emoji = source.range(of: "😀")
        _ = try await document.replaceCharacters(in: emoji, with: "🐟")
        #expect(await document.text == "let value = \"🐟\"\n")

        await #expect(throws: HighlightedDocumentError.self) {
            try await document.replaceCharacters(
                in: NSRange(location: emoji.location + 1, length: 1),
                with: "x"
            )
        }
    }

    @Test func continuationCheckpointsConvergeAndReuseSuffix() async throws {
        let lines = (0..<80).map { "let value\($0) = \($0)\n" }.joined()
        let document = try await HighlightedDocument(
            text: lines,
            selection: .named("swift"),
            checkpointInterval: 8
        )
        let range = (lines as NSString).range(of: "value1")
        let update = try await document.replaceCharacters(in: range, with: "changed")
        #expect(update.restartedAtLine == 0)
        #expect(update.convergedAtLine == 8)
        #expect(update.reparsedLineCount == 8)
        #expect(update.reusedSuffixLineCount == 73)
    }

    @Test func commentsAndHeredocsCarryContinuationAcrossLines() async throws {
        let ruby = "cat <<DOC\ninside\nDOC\necho done\n"
        let document = try await HighlightedDocument(
            text: ruby,
            selection: .named("bash"),
            checkpointInterval: 1
        )
        let snapshot = try await document.snapshot()
        let inside = (ruby as NSString).range(of: "inside")
        #expect(snapshot.tokens.contains {
            NSIntersectionRange($0.range, inside).length > 0 && $0.scope.contains("string")
        })

        let embedded = "<style>\na { color: red; }\n</style>\n"
        let embeddedDocument = try await HighlightedDocument(
            text: embedded,
            selection: .named("xml"),
            checkpointInterval: 1
        )
        let embeddedSnapshot = try await embeddedDocument.snapshot()
        #expect(embeddedSnapshot.tokens.contains {
            $0.scope == "attribute" || $0.scope == "selector-tag"
        })

        let comment = "/* open\nstill a comment\n*/\n"
        let commentDocument = try await HighlightedDocument(
            text: comment,
            selection: .named("javascript"),
            checkpointInterval: 1
        )
        let commentSnapshot = try await commentDocument.snapshot()
        let middle = (comment as NSString).range(of: "still a comment")
        #expect(commentSnapshot.tokens.contains {
            NSIntersectionRange($0.range, middle).length > 0 && $0.scope == "comment"
        })
    }

    @Test func snapshotBoundariesAtLineEdgesAndDocumentEndAreExact() async throws {
        let text = "let a = 1\nlet b = 2\n"
        let document = try await HighlightedDocument(
            text: text,
            selection: .named("swift")
        )
        let length = text.utf16.count
        let end = try await document.snapshot(in: NSRange(location: length, length: 0))
        #expect(end.text.isEmpty)
        #expect(end.tokens.isEmpty)
        #expect(end.omittedTokenCount == 0)

        let secondLine = try await document.snapshot(
            in: NSRange(location: 10, length: length - 10)
        )
        #expect(secondLine.text == "let b = 2\n")
        #expect(secondLine.tokens.contains { $0.range.location == 0 && $0.scope == "keyword" })
        #expect(secondLine.tokens.allSatisfy { NSMaxRange($0.range) <= length - 10 })
    }

    @Test func overlappingEditsApplyInArrivalOrderWithoutLostUpdates() async throws {
        let shouldBlock = Mutex(false)
        let blocked = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        let highlighter = Highlighter(languages: [
            LanguageDescriptor(name: "gated") {
                LanguageDefinition(
                    name: "gated",
                    root: Mode(contains: [Mode(
                        scope: "keyword",
                        begin: "word",
                        onBegin: { _, _ in
                            let mustWait = shouldBlock.withLock { value in
                                let first = value
                                value = false
                                return first
                            }
                            if mustWait {
                                blocked.withLock { $0 = true }
                                release.wait()
                            }
                        }
                    )])
                )
            },
        ])
        let document = try await HighlightedDocument(
            text: "word one\nword two\n",
            highlighter: highlighter,
            selection: .named("gated"),
            checkpointInterval: 1
        )
        let source = await document.text as NSString
        let oneRange = source.range(of: "one")
        let twoRange = source.range(of: "two")

        // Suspend the first edit inside its reparse, then start a second
        // edit; without arrival-order serialization the second commits
        // first and the first clobbers it with pre-edit state.
        shouldBlock.withLock { $0 = true }
        let first = Task {
            try await document.replaceCharacters(in: oneRange, with: "ONE")
        }
        while !blocked.withLock({ $0 }) { await Task.yield() }
        let second = Task {
            try await document.replaceCharacters(in: twoRange, with: "TWO")
        }
        try await Task.sleep(for: .milliseconds(20))
        release.signal()
        _ = try await first.value
        _ = try await second.value
        #expect(await document.text == "word ONE\nword TWO\n")
    }

    @Test func cancellingQueuedEditDoesNotWaitForActiveEdit() async throws {
        let shouldBlock = Mutex(false)
        let blocked = Mutex(false)
        let secondStarted = Mutex(false)
        let secondFinished = Mutex(false)
        let release = DispatchSemaphore(value: 0)
        let highlighter = Highlighter(languages: [
            LanguageDescriptor(name: "gated") {
                LanguageDefinition(
                    name: "gated",
                    root: Mode(contains: [Mode(
                        scope: "keyword",
                        begin: "word",
                        onBegin: { _, _ in
                            let mustWait = shouldBlock.withLock { value in
                                let first = value
                                value = false
                                return first
                            }
                            if mustWait {
                                blocked.withLock { $0 = true }
                                release.wait()
                            }
                        }
                    )])
                )
            },
        ])
        let document = try await HighlightedDocument(
            text: "word one\nword two\n",
            highlighter: highlighter,
            selection: .named("gated"),
            checkpointInterval: 1
        )
        let source = await document.text as NSString
        let oneRange = source.range(of: "one")
        let twoRange = source.range(of: "two")

        shouldBlock.withLock { $0 = true }
        let first = Task {
            try await document.replaceCharacters(in: oneRange, with: "ONE")
        }
        while !blocked.withLock({ $0 }) { await Task.yield() }

        let second = Task {
            secondStarted.withLock { $0 = true }
            defer { secondFinished.withLock { $0 = true } }
            return try await document.replaceCharacters(in: twoRange, with: "TWO")
        }
        while !secondStarted.withLock({ $0 }) { await Task.yield() }
        second.cancel()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while !secondFinished.withLock({ $0 }), clock.now < deadline {
            await Task.yield()
        }
        let cancelledPromptly = secondFinished.withLock { $0 }

        release.signal()
        _ = try await first.value
        do {
            _ = try await second.value
            Issue.record("cancelled queued edit unexpectedly succeeded")
        } catch is CancellationError {}

        #expect(cancelledPromptly)
        #expect(await document.text == "word ONE\nword two\n")
    }

    @Test func snapshotCapReportsExactOmission() async throws {
        let document = try await HighlightedDocument(
            text: "let a = 1\nlet b = 2\n",
            selection: .named("swift")
        )
        let full = try await document.snapshot()
        let capped = try await document.snapshot(maximumTokens: 1)
        #expect(capped.tokens.count == min(1, full.tokens.count))
        #expect(capped.omittedTokenCount == max(0, full.tokens.count - 1))
        #expect(capped.isTruncated == (full.tokens.count > 1))
    }

    @Test func failedAndCancelledEditsAreTransactional() async throws {
        let invalid = LanguageDescriptor(name: "replaceable") {
            LanguageDefinition(
                name: "replaceable",
                root: Mode(contains: [Mode(scope: "keyword", begin: "word")])
            )
        }
        let highlighter = Highlighter(languages: [invalid])
        let document = try await HighlightedDocument(
            text: "word\nword\n",
            highlighter: highlighter,
            selection: .named("replaceable"),
            checkpointInterval: 1
        )
        let original = await document.text

        highlighter.register(LanguageDescriptor(name: "replaceable") {
            LanguageDefinition(
                name: "replaceable",
                root: Mode(contains: [Mode(begin: "(")])
            )
        })
        await #expect(throws: HighlightError.self) {
            try await document.replaceCharacters(
                in: NSRange(location: 0, length: 4),
                with: "changed"
            )
        }
        #expect(await document.text == original)

        let parseStarted = Mutex(false)
        let cancellableHighlighter = Highlighter(languages: [
            LanguageDescriptor(name: "cancellable") {
                LanguageDefinition(
                    name: "cancellable",
                    root: Mode(contains: [Mode(
                        scope: "keyword",
                        begin: "word",
                        onBegin: { _, _ in parseStarted.withLock { $0 = true } }
                    )])
                )
            },
        ])
        let cancellableDocument = try await HighlightedDocument(
            text: "word\n",
            highlighter: cancellableHighlighter,
            selection: .named("cancellable"),
            checkpointInterval: 1
        )
        parseStarted.withLock { $0 = false }
        let task = Task {
            try await cancellableDocument.replaceCharacters(
                in: NSRange(location: 0, length: 4),
                with: String(repeating: "word ", count: 100_000)
            )
        }
        while !parseStarted.withLock({ $0 }) { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("mid-edit cancellation unexpectedly succeeded")
        } catch is CancellationError {}
        #expect(await cancellableDocument.text == "word\n")
    }
}
