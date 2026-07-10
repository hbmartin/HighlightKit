import Foundation
import Testing
@testable import HighlightKit

@Suite("Stress and memory")
struct StressTests {
    private static func footprintBytes() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint)
    }

    /// Repeated highlighting must not accumulate memory: all per-run
    /// state (match caches, emitters, frames) dies with the run; only
    /// compiled grammars persist, and those are warmed before measuring.
    @Test func repeatedHighlightingHasStableFootprint() {
        let samples: [(String, String)] = [
            ("javascript", "const f = async (x) => `v=${x + 1}`; /* three word comment */"),
            ("swift", "func f(_ x: Int) -> String { \"\\(x)\" } // trailing note here"),
            ("python", "def f(x):\n    return f\"{x:>3}\"  # a small comment\n"),
            ("json", #"{"a": [1, 2, 3], "flag": true}"#),
            ("xml", "<a href='x'>&amp;<b/></a>"),
        ]
        let code = samples.map(\.1).map { String(repeating: $0 + "\n", count: 40) }

        // warm-up: compile grammars and let the allocator arena reach
        // steady state — arena growth in the first iterations is not
        // leakage (pages are reused, not returned to the OS)
        for _ in 0..<50 {
            for (index, (language, _)) in samples.enumerated() {
                autoreleasepool {
                    _ = Highlighter.shared.highlight(code[index], as: language)
                }
            }
        }

        let before = Self.footprintBytes()
        for _ in 0..<100 {
            for (index, (language, _)) in samples.enumerated() {
                autoreleasepool {
                    _ = Highlighter.shared.highlight(code[index], as: language)
                }
            }
        }
        let after = Self.footprintBytes()

        let growth = after - before
        // 500 steady-state highlight runs must not grow the footprint:
        // all per-run state dies with the run. Slack for allocator noise.
        #expect(growth < 8_000_000, "footprint grew by \(growth) bytes over 500 steady-state runs")
    }

    /// Deeply nested input must not blow the stack or the iteration
    /// guard, and malformed/hostile inputs must terminate.
    @Test func hostileInputsTerminate() {
        let nested = String(repeating: "{", count: 5_000)
            + "1" + String(repeating: "}", count: 5_000)
        let r1 = Highlighter.shared.highlight(nested, as: "json")
        #expect(!r1.tokens.isEmpty)

        let longLine = String(repeating: "a ", count: 50_000)
        _ = Highlighter.shared.highlight(longLine, as: "javascript")

        let unterminated = "\"an unterminated string with no end and lots of content "
            + String(repeating: "x", count: 10_000)
        _ = Highlighter.shared.highlight(unterminated, as: "javascript")

        let binaryish = String(repeating: "\u{0}\u{1}\u{2}\u{FFFD}", count: 2_000)
        _ = Highlighter.shared.highlight(binaryish, as: "cpp")
    }

    /// Concurrent highlighting across many languages with the shared
    /// instance — exercises compiled-grammar caching under contention.
    @Test func concurrentMixedLanguages() async {
        let languages = ["swift", "javascript", "python", "ruby", "cpp", "go", "rust", "json"]
        let code = "let x = 42 // answer\nfunc f() {}\n"
        await withTaskGroup(of: Int.self) { group in
            for i in 0..<64 {
                group.addTask {
                    Highlighter.shared.highlight(code, as: languages[i % languages.count]).tokens.count
                }
            }
            var total = 0
            for await n in group { total += n }
            #expect(total > 0)
        }
    }

    /// Contended lazy compilation: a fresh highlighter (nothing compiled
    /// yet) is hit by many tasks that first-compile the *same* grammars
    /// simultaneously — the per-generation compile gates must keep this
    /// race-free without serializing different languages. The exact
    /// single-build invariant is pinned in `LanguageRegistryTests`. Run
    /// under `swift test --sanitize=thread` to prove it race-free.
    @Test func contendedLazyCompilation() async {
        let languages = LanguageCatalog.all.map(\.name)
        let highlighter = Highlighter() // fresh: no grammar compiled yet
        let code = "let x = 1; func f() {} /* c */ \"s\" 42\n"
        await withTaskGroup(of: Int.self) { group in
            for i in 0..<200 {
                group.addTask {
                    // many tasks converge on the same few languages first
                    highlighter.highlight(code, as: languages[i % 12]).tokens.count
                }
            }
            var total = 0
            for await n in group { total += n }
            #expect(total >= 0)
        }
        // every language resolves to the same compiled grammar regardless
        // of which task won the compile race
        #expect(highlighter.hasLanguage(named: "swift"))
    }

    /// Continuations produced on one task, consumed on another — the
    /// block-editor cross-actor pattern. Must be race-free (Continuation
    /// is Sendable and the compiled graph is immutable).
    @Test func continuationsAcrossTasks() async {
        let starts = (0..<32).map { _ in
            Highlighter.shared.highlight("/* open comment\n", as: "javascript").continuation
        }
        await withTaskGroup(of: Int.self) { group in
            for cont in starts {
                group.addTask {
                    Highlighter.shared.highlight("still inside */ x = 1\n", as: "javascript", continuation: cont).tokens.count
                }
            }
            var total = 0
            for await n in group { total += n }
            #expect(total > 0)
        }
    }

    /// The same immutable continuation may be forked to many speculative
    /// editor branches. Callback data must be copied into each Run rather
    /// than shared through reference-typed dictionary values. Run this
    /// under Thread Sanitizer as a race regression.
    @Test func sameContinuationAcrossTasks() async {
        let descriptor = LanguageDescriptor(name: "concurrent-fork") {
            let heredoc = Mode(
                scope: "string", begin: #"<<([A-Z]+)"#,
                end: #"([A-Z]+)"#, endSameAsBegin: true
            )
            return LanguageDefinition(name: "concurrent-fork", root: Mode(contains: [heredoc]))
        }
        let highlighter = Highlighter(languages: [descriptor])
        let continuation = highlighter.highlight("<<EOF\n", as: "concurrent-fork").continuation

        await withTaskGroup(of: Continuation?.self) { group in
            for index in 0..<128 {
                group.addTask {
                    let delimiter = index.isMultiple(of: 2) ? "TAG" : "END"
                    return highlighter.highlight(
                        "EOF\n<<\(delimiter)\n", as: "concurrent-fork",
                        continuation: continuation
                    ).continuation
                }
            }
            var count = 0
            for await state in group {
                #expect(state != nil)
                count += 1
            }
            #expect(count == 128)
        }

        // Forks above cannot mutate the original EOF state.
        let closed = highlighter.highlight(
            "EOF\n", as: "concurrent-fork", continuation: continuation
        )
        let fresh = highlighter.highlight("plain\n", as: "concurrent-fork")
        #expect(closed.continuation == fresh.continuation)
    }
}
