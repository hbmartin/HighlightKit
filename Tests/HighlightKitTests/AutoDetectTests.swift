import Foundation
import Synchronization
import Testing
@testable import HighlightKit

@Suite("Auto-detection")
struct AutoDetectTests {
    /// Pins the synchronous overload: in an `async` context a direct
    /// call would resolve to the concurrent one (SE-0296 prefers async
    /// candidates), which is exactly what these tests compare against.
    private func sequential(_ code: String, subset: [String]? = nil) -> HighlightResult {
        Highlighter.shared.highlightAuto(code, subset: subset)
    }

    private static let samples: [String] = [
        "const f = async (x) => `v=${x + 1}`; // note",
        "func f(_ x: Int) -> String { \"\\(x)\" }",
        "def f(x):\n    return f\"{x:>3}\"\n",
        #"{"a": [1, 2, 3], "flag": true}"#,
        "SELECT id, name FROM users WHERE age > 21 ORDER BY name;",
        "<html><body><p class='x'>hi</p></body></html>",
        "#include <stdio.h>\nint main(void) { printf(\"hi\\n\"); return 0; }",
        "the quick brown fox jumps over the lazy dog",
        "",
    ]

    /// The concurrent overload must be indistinguishable from the
    /// sequential one: same language, relevance, tokens, second-best.
    @Test func concurrentMatchesSequential() async {
        for code in Self.samples {
            let seq = sequential(code)
            let par = await Highlighter.shared.highlightAuto(code)
            #expect(par.language == seq.language)
            #expect(par.relevance == seq.relevance)
            #expect(par.tokens == seq.tokens)
            #expect(par.secondBest?.language == seq.secondBest?.language)
            #expect(par.secondBest?.relevance == seq.secondBest?.relevance)
        }
    }

    @Test func concurrentHonorsSubset() async {
        let code = "body { color: red; }"
        let seq = sequential(code, subset: ["xml", "css"])
        let par = await Highlighter.shared.highlightAuto(code, subset: ["xml", "css"])
        #expect(seq.language == "css")
        #expect(par.language == seq.language)
        #expect(par.tokens == seq.tokens)
        #expect(par.secondBest?.language == seq.secondBest?.language)
    }

    /// A subset naming unknown languages must not trap in either overload
    /// (unknown names are skipped; plain wins).
    @Test func concurrentSkipsUnknownSubsetEntries() async {
        let seq = sequential("hello", subset: ["nope", "also-nope"])
        let par = await Highlighter.shared.highlightAuto("hello", subset: ["nope", "also-nope"])
        #expect(seq.language == nil)
        #expect(par.language == seq.language)
    }

    @Test func boundedWindowStillRunsEveryCandidateInOrder() async {
        let candidateCount = LanguageRegistry.maximumConcurrentAutodetectTasks + 3
        let builds = Mutex(0)
        let parseHits = Mutex([Int](repeating: 0, count: candidateCount))
        let descriptors = (0..<candidateCount).map { index in
            LanguageDescriptor(name: String(format: "window-%04d", index)) {
                builds.withLock { $0 += 1 }
                return LanguageDefinition(
                    name: String(format: "window-%04d", index),
                    root: Mode(contains: [
                        Mode(
                            scope: "keyword",
                            begin: "x",
                            relevance: Double(index + 1),
                            onBegin: { _, _ in
                                parseHits.withLock { $0[index] += 1 }
                            }
                        )
                    ])
                )
            }
        }
        let registry = LanguageRegistry(languages: descriptors)

        let concurrent = await registry.highlightAuto("x", subset: nil)
        #expect(builds.withLock { $0 } == candidateCount)
        #expect(parseHits.withLock { $0 }.allSatisfy { $0 == 1 })
        #expect(concurrent.language == String(format: "window-%04d", candidateCount - 1))

        let sequential: HighlightResult = {
            registry.highlightAuto("x", subset: nil)
        }()

        #expect(concurrent.language == sequential.language)
        #expect(concurrent.relevance == sequential.relevance)
        #expect(concurrent.tokens == sequential.tokens)
        #expect(concurrent.secondBest?.language == sequential.secondBest?.language)
    }

    @Test func concurrentTieBreakPreservesRegistrationOrder() async {
        let candidateCount = LanguageRegistry.maximumConcurrentAutodetectTasks + 3
        let descriptors = (0..<candidateCount).map { index in
            LanguageDescriptor(name: String(format: "tie-%04d", index)) {
                LanguageDefinition(
                    name: String(format: "tie-%04d", index),
                    root: Mode(contains: [
                        Mode(scope: "keyword", begin: "x", relevance: 1)
                    ])
                )
            }
        }
        let result = await LanguageRegistry(languages: descriptors)
            .highlightAuto("x", subset: nil)

        #expect(result.language == "tie-0000")
        #expect(result.secondBest?.language == "tie-0001")
    }

    /// Cancellation must not crash or hang; a cancelled detection
    /// returns a ranking over whatever candidates completed.
    @Test func concurrentSurvivesCancellation() async {
        let task = Task {
            await Highlighter.shared.highlightAuto("let x = 1; // sample")
        }
        task.cancel()
        let result = await task.value
        // Either plain (all candidates skipped) or a real detection —
        // both are valid; the invariant is a well-formed result.
        #expect(result.relevance >= 0)
    }

    @Test func concurrentCancellationInterruptsAnActiveParser() async {
        let (starts, continuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        let matchCount = Mutex(0)
        let descriptor = LanguageDescriptor(name: "active-cancellation") {
            LanguageDefinition(
                name: "active-cancellation",
                root: Mode(contains: [
                    Mode(begin: "x", onBegin: { _, _ in
                        let first = matchCount.withLock { count in
                            count += 1
                            return count == 1
                        }
                        if first { continuation.yield() }
                    })
                ])
            )
        }
        let highlighter = Highlighter(languages: [descriptor])
        let inputLength = 1_000_000
        let task = Task {
            await highlighter.highlightAuto(
                String(repeating: "x", count: inputLength)
            )
        }
        var iterator = starts.makeAsyncIterator()
        _ = await iterator.next()
        task.cancel()
        let result = await task.value
        continuation.finish()

        #expect(result.language == nil)
        #expect(matchCount.withLock { $0 } < inputLength)
    }

}
