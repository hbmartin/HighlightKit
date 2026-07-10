import Foundation
import Testing
@testable import HighlightKit

/// Throughput measurements — opt-in via `HIGHLIGHT_BENCH=1 swift test -c
/// release --filter Performance`. Kept out of the default run so CI time
/// stays flat; correctness is covered elsewhere.
@Suite(
    "Performance",
    .enabled(if: ProcessInfo.processInfo.environment["HIGHLIGHT_BENCH"] == "1")
)
struct PerformanceTests {
    static let sampleJS = """
    // Fibonacci with memoization
    const memo = new Map();
    function fib(n) {
        if (n <= 1) return n;
        if (memo.has(n)) return memo.get(n);
        const value = fib(n - 1) + fib(n - 2);
        memo.set(n, value);
        return value;
    }
    class Sequence {
        constructor(limit = 100) { this.limit = limit; }
        *values() {
            for (let i = 0; i < this.limit; i++) yield fib(i);
        }
    }
    const seq = new Sequence(50);
    console.log([...seq.values()].join(", "));
    const template = `total: ${[...seq.values()].reduce((a, b) => a + b, 0)}`;
    /* block comment with some prose in it — three words here */
    export default { fib, Sequence };

    """

    @Test func throughput() {
        let code = String(repeating: Self.sampleJS, count: 100) // ~90 KB
        let bytes = (code as NSString).length

        // warm up (grammar compile)
        _ = Highlighter.shared.highlight(code, as: "javascript")

        let runs = Int(ProcessInfo.processInfo.environment["HIGHLIGHT_BENCH_RUNS"] ?? "5") ?? 5
        let start = ContinuousClock.now
        var tokenCount = 0
        for _ in 0..<runs {
            tokenCount = Highlighter.shared.highlight(code, as: "javascript").tokens.count
        }
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        let mbPerSecond = Double(bytes * runs) / seconds / 1_000_000

        print("[bench] javascript: \(bytes) utf16 units × \(runs) runs in \(seconds)s → \(String(format: "%.2f", mbPerSecond)) MU/s, \(tokenCount) tokens")
        #expect(tokenCount > 0)
        // regression guard: anything below ~0.3 MB/s signals something
        // pathological (JSCore-based highlighting is around this mark)
        #expect(mbPerSecond > 0.3)
    }

    @Test func firstHighlightIncludesCompileCost() {
        let highlighter = Highlighter()
        let start = ContinuousClock.now
        _ = highlighter.highlight("const x = 1;", as: "javascript")
        let elapsed = ContinuousClock.now - start
        let ms = Double(elapsed.components.seconds) * 1000
            + Double(elapsed.components.attoseconds) / 1e15
        print("[bench] cold javascript compile+highlight: \(String(format: "%.1f", ms))ms")
        #expect(ms < 500)
    }
}

#if DEBUG_MATCH_STATS
extension PerformanceTests {
    /// Per-rule cost profile. `HIGHLIGHT_PROFILE_LANG` picks the grammar
    /// (default javascript); `HIGHLIGHT_PROFILE_FILE` supplies real code
    /// to highlight (repeated to ~60 KB), defaulting to the JS sample.
    @Test func ruleCosts() {
        let env = ProcessInfo.processInfo.environment
        let language = env["HIGHLIGHT_PROFILE_LANG"] ?? "javascript"
        var code = String(repeating: Self.sampleJS, count: 100)
        if let path = env["HIGHLIGHT_PROFILE_FILE"],
           let contents = try? String(contentsOfFile: path, encoding: .utf8) {
            let copies = max(1, 60_000 / max(1, (contents as NSString).length))
            code = String(repeating: contents, count: copies)
        }
        _ = Highlighter.shared.highlight(code, as: language)
        MatchStats.dumpTop(14)
    }
}
#endif
