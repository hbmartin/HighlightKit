import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import HighlightKit
import Synchronization

// Standalone benchmark / leak-check host.
//
//   swift run -c release highlight-bench [runs] [language] [file]
//   leaks --atExit -- .build/debug/highlight-bench 50
//
// Without a file argument, a built-in JavaScript sample (~62k UTF-16
// units) is used.

let sampleJS = String(repeating: """
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

""", count: 100)

let arguments = CommandLine.arguments

/// Drains temporary Objective-C objects in bounded batches on Apple
/// platforms while keeping the benchmark host source portable.
func withBenchmarkAutoreleasePool<Result>(
    _ body: () throws -> Result
) rethrows -> Result {
    #if canImport(ObjectiveC)
    try autoreleasepool(invoking: body)
    #else
    try body()
    #endif
}

// These consumers make the benchmark result observable without folding
// ownership traffic into the operation under test. `@inline(never)` is a
// benchmark-only guard against dead-code elimination, not a production
// optimization hint.
@inline(never)
func themeChecksum(_ theme: borrowing HighlightTheme) -> Int {
    theme.styles.count &* 31 &+ Int(theme.font.size)
}

@inline(never)
func attributedChecksum(_ string: borrowing NSAttributedString) -> Int {
    string.length
}

func measureThemeBenchmark(
    iterations: Int,
    operation: () -> Int
) -> (seconds: Double, checksum: Int) {
    var checksum = 0
    var remaining = iterations
    let start = ContinuousClock.now

    // Amortize pool entry while bounding temporary colors, dictionaries,
    // and attributed strings retained by Objective-C autorelease semantics.
    while remaining > 0 {
        let count = min(remaining, 256)
        withBenchmarkAutoreleasePool {
            for _ in 0..<count {
                checksum &+= operation()
            }
        }
        remaining -= count
    }

    let elapsed = ContinuousClock.now - start
    let seconds = Double(elapsed.components.seconds)
        + Double(elapsed.components.attoseconds) / 1e18
    return (seconds, checksum)
}

final class RegistryBuildCounter: Sendable {
    let value = Mutex(0)
}

actor RegistryStartBarrier {
    let participantCount: Int
    var waiters: [CheckedContinuation<Void, Never>] = []

    init(participantCount: Int) {
        self.participantCount = participantCount
        waiters.reserveCapacity(participantCount)
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            guard waiters.count == participantCount else { return }
            let ready = waiters
            waiters.removeAll(keepingCapacity: false)
            for waiter in ready { waiter.resume() }
        }
    }
}

func benchmarkSeconds(_ body: () -> Void) -> Double {
    let start = ContinuousClock.now
    body()
    let elapsed = ContinuousClock.now - start
    return Double(elapsed.components.seconds)
        + Double(elapsed.components.attoseconds) / 1e18
}

/// Stable, process-independent FNV-1a used only to prove that two benchmark
/// executables produced the same observable highlighting result. Swift's
/// `Hasher` is intentionally randomized per process and is therefore not
/// suitable for an A/B correctness checksum.
struct AutoBenchmarkChecksum {
    private(set) var value: UInt64 = 0xcbf29ce484222325

    mutating func append(byte: UInt8) {
        value ^= UInt64(byte)
        value &*= 0x100000001b3
    }

    mutating func append(_ integer: Int) {
        append(UInt64(truncatingIfNeeded: integer))
    }

    mutating func append(_ integer: UInt64) {
        for shift in stride(from: 0, to: 64, by: 8) {
            append(byte: UInt8(truncatingIfNeeded: integer >> UInt64(shift)))
        }
    }

    mutating func append(_ value: Double) {
        append(value.bitPattern)
    }

    mutating func append(_ value: Bool) {
        append(byte: value ? 1 : 0)
    }

    mutating func append(_ string: String) {
        append(string.utf8.count)
        for byte in string.utf8 { append(byte: byte) }
    }

    mutating func append(_ string: String?) {
        guard let string else {
            append(byte: 0)
            return
        }
        append(byte: 1)
        append(string)
    }
}

@inline(never)
func autoResultChecksum(_ result: borrowing HighlightResult) -> UInt64 {
    var checksum = AutoBenchmarkChecksum()
    checksum.append(result.language)
    checksum.append(result.relevance)
    checksum.append(result.illegal)
    checksum.append(result.tokens.count)
    for token in result.tokens {
        checksum.append(token.range.location)
        checksum.append(token.range.length)
        checksum.append(token.scopes.count)
        for scope in token.scopes { checksum.append(scope) }
    }
    if let secondBest = result.secondBest {
        checksum.append(byte: 1)
        checksum.append(secondBest.language)
        checksum.append(secondBest.relevance)
    } else {
        checksum.append(byte: 0)
    }
    return checksum.value
}

func autoInputChecksum(_ code: String) -> UInt64 {
    var checksum = AutoBenchmarkChecksum()
    checksum.append(code)
    return checksum.value
}

/// Top-level `await` alone does not participate in overload selection and can
/// choose the synchronous `highlightAuto` overload. Crossing an explicitly
/// async helper makes the benchmark exercise the concurrent public API.
func concurrentAutoResult(
    _ highlighter: Highlighter,
    code: String
) async -> HighlightResult {
    await highlighter.highlightAuto(code)
}

struct AutoBenchmarkRecord: Encodable {
    let schemaVersion: Int
    let benchmark: String
    let scenario: String
    let iterations: Int
    let utf16Units: Int
    let languageCount: Int
    let totalElapsedSeconds: Double
    let nanosecondsPerOperation: Double
    let inputChecksum: String
    let semanticChecksum: String
    let resultChecksum: String
    let detectedLanguage: String?
    let relevance: Double
    let tokenCount: Int
}

// Tokenizer mode for differential testing against highlight.js:
//   highlight-bench --tokens <language> <file>
// emits {"language","relevance","tokens":[{"start","length","scopes"}]}
// on stdout, matching scratchpad/hljs-ref/gen-fixtures.mjs exactly.
if arguments.count >= 4, arguments[1] == "--tokens" {
    let lang = arguments[2]
    let code = (try? String(contentsOfFile: arguments[3], encoding: .utf8)) ?? ""
    let result = Highlighter.shared.highlight(code, as: lang, ignoreIllegals: true)
    func jsonString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let c where c.value < 0x20: out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
    var lines: [String] = []
    for t in result.tokens {
        let scopes = t.scopes.map(jsonString).joined(separator: ",")
        lines.append("{\"start\":\(t.range.location),\"length\":\(t.range.length),\"scopes\":[\(scopes)]}")
    }
    let langField = result.language.map(jsonString) ?? "null"
    print("{\"language\":\(langField),\"relevance\":\(result.relevance),\"tokens\":[\(lines.joined(separator: ","))]}")
    exit(0)
}

// Batch tokenizer for differential testing: reads JSONL {"lang","code"}
// from stdin, emits JSONL {"tokens","relevance"} — one line per input.
if arguments.count >= 2, arguments[1] == "--tokens-batch" {
    func jsonString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case let c where c.value < 0x20: out += String(format: "\\u%04x", c.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
    struct Input: Decodable { let lang: String; let code: String }
    while let line = readLine(strippingNewline: true) {
        if line.isEmpty { print("{}"); continue }
        guard let data = line.data(using: .utf8),
              let input = try? JSONDecoder().decode(Input.self, from: data) else {
            print("{\"error\":\"bad input\"}")
            continue
        }
        let result = Highlighter.shared.highlight(input.code, as: input.lang, ignoreIllegals: true)
        var toks: [String] = []
        for t in result.tokens {
            let scopes = t.scopes.map(jsonString).joined(separator: ",")
            toks.append("{\"start\":\(t.range.location),\"length\":\(t.range.length),\"scopes\":[\(scopes)]}")
        }
        print("{\"tokens\":[\(toks.joined(separator: ","))],\"relevance\":\(result.relevance)}")
    }
    exit(0)
}


// Incremental-consistency check for differential testing: reads JSONL
// {"lang","code"}, highlights the code whole and line-by-line (threading
// the continuation), and emits {"consistent":bool,"mismatchAt":Int?}.
if arguments.count >= 2, arguments[1] == "--incremental-check" {
    func scopeMap(_ result: HighlightResult, base: Int, into map: inout [Int: String]) {
        for t in result.tokens {
            for i in 0..<t.range.length { map[base + t.range.location + i] = t.scope }
        }
    }
    struct Input: Decodable { let lang: String; let code: String }
    while let line = readLine(strippingNewline: true) {
        if line.isEmpty { print("{}"); continue }
        guard let data = line.data(using: .utf8),
              let input = try? JSONDecoder().decode(Input.self, from: data) else {
            print("{\"error\":\"bad input\"}"); continue
        }
        var whole: [Int: String] = [:]
        scopeMap(Highlighter.shared.highlight(input.code, as: input.lang), base: 0, into: &whole)
        var incr: [Int: String] = [:]
        var cont: Continuation?
        var base = 0
        let ns = input.code as NSString
        // split into lines keeping the trailing newline on each
        var start = 0
        while start < ns.length {
            var end = start
            while end < ns.length, ns.character(at: end) != 10 { end += 1 }
            if end < ns.length { end += 1 } // include the \n
            let lineText = ns.substring(with: NSRange(location: start, length: end - start))
            let r = Highlighter.shared.highlight(lineText, as: input.lang, continuation: cont)
            cont = r.continuation
            scopeMap(r, base: base, into: &incr)
            base += (lineText as NSString).length
            start = end
        }
        var mismatch = -1
        for i in 0..<ns.length where whole[i] != incr[i] { mismatch = i; break }
        print("{\"consistent\":\(mismatch < 0),\"mismatchAt\":\(mismatch)}")
    }
    exit(0)
}


// Theme construction and small-block rendering benchmark:
//   highlight-bench --theme-bench <scenario> <iterations>
// Scenarios: theme-get, registry-get, one-call, pure-render, theme-cold.
if arguments.count >= 4, arguments[1] == "--theme-bench" {
    let scenario = arguments[2]
    let iterations = max(1, Int(arguments[3]) ?? 1)
    if scenario == "theme-cold", iterations != 1 {
        print("theme-cold requires exactly one iteration")
        exit(EXIT_FAILURE)
    }

    let code = "let value = 42 // comment\n"
    let highlighter = Highlighter.shared
    // Warms grammar compilation for every scenario without touching a
    // theme. Cold theme timing therefore remains a true first access.
    let result = highlighter.highlight(code, as: "swift")

    let operation: () -> Int
    switch scenario {
    case "theme-get", "theme-cold":
        operation = { themeChecksum(.github) }
    case "registry-get":
        operation = { themeChecksum(HighlightTheme.named("github")!) }
    case "one-call":
        operation = {
            attributedChecksum(
                highlighter.attributedString(for: code, language: "swift")
            )
        }
    case "pure-render":
        // The prebuilt theme makes this a negative control for renderer
        // throughput; it must not include theme construction/access cost.
        let theme = HighlightTheme.github
        operation = {
            attributedChecksum(result.attributedString(for: code, theme: theme))
        }
    default:
        print("expected theme-get, registry-get, one-call, pure-render, or theme-cold")
        exit(EXIT_FAILURE)
    }

    if scenario != "theme-cold" {
        _ = withBenchmarkAutoreleasePool { operation() }
    }
    let measurement = measureThemeBenchmark(
        iterations: iterations,
        operation: operation
    )
    let nsPerOperation = measurement.seconds / Double(iterations) * 1e9
    print(
        "theme-bench,\(scenario),\(iterations)," +
        "\(String(format: "%.6f", nsPerOperation)),\(measurement.checksum)"
    )
    exit(EXIT_SUCCESS)
}

// Registry benchmark:
//   highlight-bench --registry-bench warm-highlight <iterations>
//   highlight-bench --registry-bench auto-warm <iterations>
//   highlight-bench --registry-bench cold-contention <tasks> [rounds]
//   highlight-bench --registry-bench warm-contention <tasks> [operations]
//
// The first two are warm-path latency controls. `warm-contention` probes
// the per-generation cache under simultaneous reads. `cold-contention`
// also reports the exact descriptor build count: one build per round is
// the required invariant regardless of task count.
if arguments.count >= 4, arguments[1] == "--registry-bench" {
    let scenario = arguments[2]

    switch scenario {
    case "warm-highlight":
        let iterations = max(1, Int(arguments[3]) ?? 1)
        let builds = RegistryBuildCounter()
        let descriptor = LanguageDescriptor(name: "registry-bench", aliases: ["rb"]) {
            builds.value.withLock { $0 += 1 }
            return LanguageDefinition(
                name: "registry-bench",
                root: Mode(contains: [Mode(scope: "keyword", begin: "x")])
            )
        }
        let highlighter = Highlighter(languages: [descriptor])
        _ = highlighter.highlight("x", as: "rb")
        var checksum = 0
        let seconds = benchmarkSeconds {
            for _ in 0..<iterations {
                withBenchmarkAutoreleasePool {
                    checksum &+= highlighter.highlight("x", as: "rb").tokens.count
                }
            }
        }
        print(
            "registry-bench,warm-highlight,\(iterations)," +
            "\(String(format: "%.6f", seconds / Double(iterations) * 1e9))," +
            "\(builds.value.withLock { $0 }),\(checksum)"
        )

    case "auto-warm":
        let iterations = max(1, Int(arguments[3]) ?? 1)
        let languageCount = 64
        let descriptors = (0..<languageCount).map { index in
            LanguageDescriptor(name: "auto-\(index)") {
                LanguageDefinition(
                    name: "auto-\(index)",
                    root: Mode(contains: [Mode(scope: "keyword", begin: "x")])
                )
            }
        }
        let highlighter = Highlighter(languages: descriptors)
        for index in 0..<languageCount {
            _ = highlighter.highlight("", as: "auto-\(index)")
        }
        _ = highlighter.highlightAuto("x")
        var checksum = 0
        let seconds = benchmarkSeconds {
            for _ in 0..<iterations {
                withBenchmarkAutoreleasePool {
                    let result = highlighter.highlightAuto("x")
                    checksum &+= result.tokens.count &+ Int(result.relevance)
                }
            }
        }
        print(
            "registry-bench,auto-warm,\(iterations)," +
            "\(String(format: "%.6f", seconds / Double(iterations) * 1e9))," +
            "\(languageCount),\(checksum)"
        )

    case "cold-contention":
        let taskCount = max(1, Int(arguments[3]) ?? 1)
        let rounds = arguments.count > 4 ? max(1, Int(arguments[4]) ?? 1) : 1
        let builds = RegistryBuildCounter()
        var checksum = 0
        let start = ContinuousClock.now
        for _ in 0..<rounds {
            let descriptor = LanguageDescriptor(name: "contended") {
                builds.value.withLock { $0 += 1 }
                var modes: [Mode] = []
                modes.reserveCapacity(128)
                for index in 0..<128 {
                    modes.append(Mode(scope: "keyword", begin: "token\(index)"))
                }
                return LanguageDefinition(
                    name: "contended",
                    root: Mode(contains: modes)
                )
            }
            let highlighter = Highlighter(languages: [descriptor])
            let barrier = RegistryStartBarrier(participantCount: taskCount)
            await withTaskGroup(of: Int.self) { group in
                for _ in 0..<taskCount {
                    group.addTask {
                        await barrier.wait()
                        return highlighter.highlight(
                            "token127",
                            as: "contended"
                        ).tokens.count
                    }
                }
                for await count in group { checksum &+= count }
            }
        }
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        print(
            "registry-bench,cold-contention,\(taskCount),\(rounds)," +
            "\(String(format: "%.6f", seconds / Double(rounds) * 1e9))," +
            "\(builds.value.withLock { $0 }),\(checksum)"
        )

    case "warm-contention":
        let taskCount = max(1, Int(arguments[3]) ?? 1)
        let operationCount = arguments.count > 4
            ? max(taskCount, Int(arguments[4]) ?? taskCount)
            : 200_000
        let builds = RegistryBuildCounter()
        let descriptor = LanguageDescriptor(name: "warm-contended", aliases: ["wc"]) {
            builds.value.withLock { $0 += 1 }
            return LanguageDefinition(
                name: "warm-contended",
                root: Mode(contains: [Mode(scope: "keyword", begin: "x")])
            )
        }
        let highlighter = Highlighter(languages: [descriptor])
        _ = highlighter.highlight("x", as: "wc")

        let barrier = RegistryStartBarrier(participantCount: taskCount)
        var checksum = 0
        let start = ContinuousClock.now
        await withTaskGroup(of: Int.self) { group in
            for taskIndex in 0..<taskCount {
                let baseCount = operationCount / taskCount
                let localCount = baseCount + (taskIndex < operationCount % taskCount ? 1 : 0)
                group.addTask {
                    await barrier.wait()
                    var localChecksum = 0
                    for _ in 0..<localCount {
                        withBenchmarkAutoreleasePool {
                            localChecksum &+= highlighter.highlight("x", as: "wc").tokens.count
                        }
                    }
                    return localChecksum
                }
            }
            for await localChecksum in group {
                checksum &+= localChecksum
            }
        }
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        print(
            "registry-bench,warm-contention,\(taskCount),\(operationCount)," +
            "\(String(format: "%.6f", seconds / Double(operationCount) * 1e9))," +
            "\(builds.value.withLock { $0 }),\(checksum)"
        )

    default:
        print("expected warm-highlight, auto-warm, cold-contention, or warm-contention")
        exit(EXIT_FAILURE)
    }
    exit(EXIT_SUCCESS)
}

// Rendering benchmark: highlight once, then time repeated
// attributedString(for:theme:) generation — the block-editor
// re-render workload. `highlight-bench --render <iters> [language]`.
if arguments.count >= 3, arguments[1] == "--render" {
    let iters = Int(arguments[2]) ?? 100
    let lang = arguments.count > 3 ? arguments[3] : "javascript"
    let code = sampleJS
    let result = Highlighter.shared.highlight(code, as: lang)
    let theme = HighlightTheme.githubDark
    _ = result.attributedString(for: code, theme: theme) // warm
    let start = ContinuousClock.now
    var total = 0
    for _ in 0..<iters {
        withBenchmarkAutoreleasePool {
            total += result.attributedString(for: code, theme: theme).length
        }
    }
    let el = ContinuousClock.now - start
    let sec = Double(el.components.seconds) + Double(el.components.attoseconds)/1e18
    let units = (code as NSString).length
    print("render \(lang): \(result.tokens.count) tokens × \(iters) → \(String(format: "%.2f", Double(units*iters)/sec/1e6)) MU/s, \(String(format: "%.1f", sec/Double(iters)*1e6))µs/render")
    exit(0)
}

// Auto-detection benchmark: `highlight-bench --auto <iters> [file]`.
// The paste-time "which language is this?" path. Cold = fresh
// Highlighter instance (compiles every grammar); warm = repeated
// detection on an already-compiled instance. Sequential vs concurrent.
// Default input is one paste-sized copy of the JS sample (~622 units).
//
// Machine-readable async A/B mode:
//   highlight-bench --auto-bench <cold|warm> <iterations> [file]
// Cold timing includes a fresh Highlighter and grammar compilation in every
// operation. Warm timing uses one dedicated instance and excludes one async
// warm-up. Checksumming is outside the timed regions.
if arguments.count >= 2, arguments[1] == "--auto-bench" {
    guard arguments.count >= 4,
          arguments[2] == "cold" || arguments[2] == "warm",
          let iterations = Int(arguments[3]),
          iterations > 0
    else {
        fputs(
            "usage: highlight-bench --auto-bench <cold|warm> " +
                "<positive-iterations> [file]\n",
            stderr
        )
        exit(EXIT_FAILURE)
    }

    let scenario = arguments[2]
    let code: String
    if arguments.count > 4 {
        guard let input = try? String(
            contentsOfFile: arguments[4],
            encoding: .utf8
        ) else {
            fputs("could not read UTF-8 input: \(arguments[4])\n", stderr)
            exit(EXIT_FAILURE)
        }
        code = input
    } else {
        code = String(sampleJS.prefix(sampleJS.count / 100))
    }

    var elapsedSeconds = 0.0
    var aggregateChecksum = AutoBenchmarkChecksum()
    var finalResult: HighlightResult?

    if scenario == "cold" {
        for iteration in 0..<iterations {
            let start = ContinuousClock.now
            let highlighter = Highlighter()
            let result = await concurrentAutoResult(highlighter, code: code)
            let elapsed = ContinuousClock.now - start
            elapsedSeconds += Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18

            // Keep all semantic work outside the timed interval. Folding the
            // iteration index prevents even identical results from cancelling
            // one another in the aggregate checksum.
            aggregateChecksum.append(iteration)
            aggregateChecksum.append(autoResultChecksum(result))
            finalResult = result
        }
    } else {
        let highlighter = Highlighter()
        _ = await concurrentAutoResult(highlighter, code: code)
        for iteration in 0..<iterations {
            let start = ContinuousClock.now
            let result = await concurrentAutoResult(highlighter, code: code)
            let elapsed = ContinuousClock.now - start
            elapsedSeconds += Double(elapsed.components.seconds)
                + Double(elapsed.components.attoseconds) / 1e18

            aggregateChecksum.append(iteration)
            aggregateChecksum.append(autoResultChecksum(result))
            finalResult = result
        }
    }

    // `iterations` is strictly positive, so this cannot be nil.
    let result = finalResult!
    let record = AutoBenchmarkRecord(
        schemaVersion: 1,
        benchmark: "async-auto-detect",
        scenario: scenario,
        iterations: iterations,
        utf16Units: (code as NSString).length,
        languageCount: Highlighter.shared.languageNames.count,
        totalElapsedSeconds: elapsedSeconds,
        nanosecondsPerOperation: elapsedSeconds / Double(iterations) * 1e9,
        inputChecksum: String(format: "%016llx", autoInputChecksum(code)),
        semanticChecksum: String(
            format: "%016llx",
            aggregateChecksum.value
        ),
        resultChecksum: String(format: "%016llx", autoResultChecksum(result)),
        detectedLanguage: result.language,
        relevance: result.relevance,
        tokenCount: result.tokens.count
    )
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try! encoder.encode(record)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0a]))
    exit(EXIT_SUCCESS)
}

if arguments.count >= 3, arguments[1] == "--auto" {
    let iters = max(1, Int(arguments[2]) ?? 5)
    let code: String
    if arguments.count > 3 {
        code = (try? String(contentsOfFile: arguments[3], encoding: .utf8)) ?? sampleJS
    } else {
        code = String(sampleJS.prefix(sampleJS.count / 100))
    }
    let units = (code as NSString).length

    func measure(_ body: () -> Void) -> Double {
        let start = ContinuousClock.now
        body()
        let el = ContinuousClock.now - start
        return Double(el.components.seconds) + Double(el.components.attoseconds) / 1e18
    }
    func measureAsync(_ body: () async -> Void) async -> Double {
        let start = ContinuousClock.now
        await body()
        let el = ContinuousClock.now - start
        return Double(el.components.seconds) + Double(el.components.attoseconds) / 1e18
    }

    var detected: String?
    let coldSeq = measure {
        let fresh = Highlighter()
        detected = fresh.highlightAuto(code).language
    }
    let coldPar = await measureAsync {
        let fresh = Highlighter()
        _ = await fresh.highlightAuto(code)
    }
    _ = Highlighter.shared.highlightAuto(code) // warm the shared instance
    var warmSeq = 0.0
    var warmPar = 0.0
    for _ in 0..<iters {
        warmSeq += measure { withBenchmarkAutoreleasePool { _ = Highlighter.shared.highlightAuto(code) } }
    }
    for _ in 0..<iters {
        warmPar += await measureAsync { _ = await Highlighter.shared.highlightAuto(code) }
    }
    let langCount = Highlighter.shared.languageNames.count
    print("auto-detect (\(units) units, \(langCount) languages) → \(detected ?? "nil")")
    print(String(format: "  cold  sequential %7.1f ms   concurrent %7.1f ms  (%.1f×)", coldSeq * 1000, coldPar * 1000, coldSeq / coldPar))
    print(String(format: "  warm  sequential %7.1f ms   concurrent %7.1f ms  (%.1f×)", warmSeq / Double(iters) * 1000, warmPar / Double(iters) * 1000, warmSeq / warmPar))
    exit(0)
}

let runs = arguments.count > 1 ? Int(arguments[1]) ?? 5 : 5
let language = arguments.count > 2 ? arguments[2] : "javascript"

// Incremental mode: `highlight-bench <iters> <language> --incremental`
// highlights the sample one *line* at a time, threading the continuation
// — the block-editor workload, where per-call fixed cost dominates.
if arguments.count > 3, arguments[3] == "--incremental" {
    let lines = sampleJS.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    _ = Highlighter.shared.highlight(sampleJS, as: language) // warm compile
    let start = ContinuousClock.now
    var totalTokens = 0
    for _ in 0..<runs {
        var continuation: Continuation?
        for line in lines {
            withBenchmarkAutoreleasePool {
                let r = Highlighter.shared.highlight(line + "\n", as: language, continuation: continuation)
                continuation = r.continuation
                totalTokens += r.tokens.count
            }
        }
    }
    let elapsed = ContinuousClock.now - start
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    let calls = runs * lines.count
    let usPerCall = seconds / Double(calls) * 1e6
    print("incremental \(language): \(calls) line-highlights in \(String(format: "%.9f", seconds))s → \(String(format: "%.6f", usPerCall)) µs/line, \(totalTokens) tokens")
    exit(0)
}

let code: String
if arguments.count > 3 {
    code = (try? String(contentsOfFile: arguments[3], encoding: .utf8)) ?? sampleJS
} else {
    code = sampleJS
}

let units = (code as NSString).length

// warm-up (grammar compilation)
_ = Highlighter.shared.highlight(code, as: language)

let start = ContinuousClock.now
var tokenCount = 0
for _ in 0..<runs {
    withBenchmarkAutoreleasePool {
        tokenCount = Highlighter.shared.highlight(code, as: language).tokens.count
    }
}
let elapsed = ContinuousClock.now - start
let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
let throughput = Double(units * runs) / seconds / 1_000_000

print("\(language): \(units) utf16 units × \(runs) runs in \(String(format: "%.9f", seconds))s → \(String(format: "%.6f", throughput)) MU/s, \(tokenCount) tokens")
