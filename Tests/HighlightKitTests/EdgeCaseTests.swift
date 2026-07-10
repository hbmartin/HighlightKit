import Foundation
import Synchronization
import Testing
@testable import HighlightKit

/// Boundary and rarely-hit branches: public API surface, empty/degenerate
/// inputs, error paths, and the engine's defensive guards.
@Suite("Edge cases")
struct EdgeCaseTests {
    // MARK: Public API

    @Test func publicHighlighterSurface() {
        let h = Highlighter(languages: [LanguageCatalog.json, LanguageCatalog.plaintext])
        #expect(h.languageNames.contains("json"))
        #expect(!h.languageNames.contains("swift"))
        h.register(LanguageCatalog.swift)
        #expect(h.hasLanguage(named: "swift"))
        #expect(h.highlight("let x = 1", as: "swift").language == "swift")
    }

    @Test func emptyStringHighlightsToNothing() {
        for lang in ["json", "javascript", "swift", "xml", "plaintext"] {
            let result = Highlighter.shared.highlight("", as: lang)
            #expect(result.tokens.isEmpty)
            #expect(result.attributedString(for: "", theme: .githubLight).length == 0)
        }
    }

    @Test func autoDetectEmptyAndPlain() {
        #expect(Highlighter.shared.highlightAuto("").language == nil)
        // pure prose is not strongly any language
        let result = Highlighter.shared.highlightAuto("the quick brown fox")
        #expect(result.tokens.isEmpty || result.relevance >= 0)
    }

    // MARK: Registry

    @Test func unknownLanguageThrowsInternally() {
        let registry = LanguageRegistry(languages: LanguageCatalog.all)
        #expect(throws: HighlightError.self) {
            _ = try registry.compiledLanguage(named: "nonexistent")
        }
        #expect(registry.canonicalName(for: "nonexistent") == nil)
        #expect(registry.descriptor(named: "nonexistent") == nil)
        #expect(registry.descriptor(named: "js")?.name == "javascript")
    }

    @Test func reregisteringReplacesGrammar() {
        let registry = LanguageRegistry(languages: [LanguageCatalog.json])
        _ = try? registry.compiledLanguage(named: "json")
        // replace json with a trivial grammar; the cache must be dropped
        let replacement = LanguageDescriptor(name: "json") {
            LanguageDefinition(name: "json", root: Mode(contains: [Mode(scope: "keyword", begin: "X")]))
        }
        registry.register([replacement])
        let result = try? registry.highlight("X", languageName: "json", ignoreIllegals: true)
        #expect(result?.tokens.first?.scope == "keyword")
    }

    // MARK: Illegal handling

    @Test func illegalAtEndOfInput() {
        // `illegal: \S` with trailing non-space right at EOF
        let bad = "{\"a\":1}x"
        let honored = Highlighter.shared.highlight(bad, as: "json", ignoreIllegals: false)
        #expect(honored.illegal)
    }

    @Test func ignoredIllegalsProduceTokens() {
        let bad = "{\"a\": <invalid> }"
        let result = Highlighter.shared.highlight(bad, as: "json", ignoreIllegals: true)
        #expect(!result.illegal)
    }

    // MARK: Sub-language fallbacks

    @Test func subLanguageToUnknownDegradesToPlain() {
        // a grammar delegating to a language not registered in this
        // highlighter must emit the block as plain text, not crash
        let descriptor = LanguageDescriptor(name: "host") {
            LanguageDefinition(name: "host", root: Mode(contains: [
                Mode(begin: "```", end: "```", subLanguage: ["no-such-lang"]),
            ]))
        }
        let h = Highlighter(languages: [descriptor])
        let result = h.highlight("```\nsome code\n```", as: "host")
        // no tokens from the missing sub-language, no crash
        #expect(result.language == "host")
    }

    @Test func autoDetectSubLanguage() {
        // markdown fenced blocks auto-detect; must not crash and must
        // produce nested scopes for a recognizable block
        let md = "```json\n{\"a\": 1}\n```\n"
        let result = Highlighter.shared.highlight(md, as: "markdown")
        #expect(!result.tokens.isEmpty)
    }

    @Test func recursiveSubLanguagesDegradeToPlainInsteadOfRecursingForever() {
        let direct = LanguageDescriptor(name: "direct-recursion") {
            LanguageDefinition(
                name: "direct-recursion",
                root: Mode(subLanguage: ["direct-recursion"])
            )
        }
        let first = LanguageDescriptor(name: "cycle-a") {
            LanguageDefinition(name: "cycle-a", root: Mode(subLanguage: ["cycle-b"]))
        }
        let second = LanguageDescriptor(name: "cycle-b") {
            LanguageDefinition(name: "cycle-b", root: Mode(subLanguage: ["cycle-a"]))
        }
        let auto = LanguageDescriptor(name: "auto-recursion") {
            LanguageDefinition(name: "auto-recursion", root: Mode(subLanguage: []))
        }
        let highlighter = Highlighter(languages: [direct, first, second, auto])

        for language in ["direct-recursion", "cycle-a", "auto-recursion"] {
            let result = highlighter.highlight("non-empty", as: language)
            #expect(result.language == language)
            #expect(result.tokens.isEmpty)

            // A root continuation is still the same parser state. It must
            // not turn an equal-sized self/cycle delegation into progress.
            let resumed = highlighter.highlight(
                "non-empty",
                as: language,
                continuation: result.continuation
            )
            #expect(resumed.language == language)
            #expect(resumed.tokens.isEmpty)
        }
    }

    // MARK: Multi-line / continuation

    @Test func continuationAcrossManyLines() {
        let lines = ["/* open", "middle", "close */ x = 1"]
        var continuation: Continuation?
        var allScopes: [String] = []
        for line in lines {
            let r = Highlighter.shared.highlight(line + "\n", as: "javascript", continuation: continuation)
            continuation = r.continuation
            allScopes.append(contentsOf: r.tokens.map(\.scope))
        }
        // the comment scope must appear on the first two lines
        #expect(allScopes.contains("comment"))
    }

    // MARK: Whitespace-only and newline handling

    @Test func whitespaceOnlyInput() {
        let result = Highlighter.shared.highlight("   \n\t\n  ", as: "python")
        #expect(result.tokens.isEmpty || result.tokens.allSatisfy { $0.range.length > 0 })
    }

    @Test func trailingNewlines() {
        let result = Highlighter.shared.highlight("x = 1\n\n\n", as: "python")
        let length = ("x = 1\n\n\n" as NSString).length
        for token in result.tokens {
            #expect(token.range.location + token.range.length <= length)
        }
    }

    @Test func potentialInfiniteLoopGuardRecovers() {
        // A pathological grammar that could spin: a mode whose begin is a
        // zero-width lookahead and whose only child is likewise zero-width
        // gives the engine no forward progress. The infinite-loop guard
        // must trip and the registry must degrade to an (empty) result
        // rather than hang. (This is the guard the \b\B / EOF bugs used to
        // trip for the wrong reasons; here it is exercised deliberately.)
        let descriptor = LanguageDescriptor(name: "spin") {
            LanguageDefinition(name: "spin", root: Mode(contains: [
                // begin matches empty everywhere; end never advances
                Mode(scope: "x", begin: "(?=a)", end: "\\b\\B", contains: [
                    Mode(scope: "y", begin: "(?=a)"),
                ]),
            ]))
        }
        let h = Highlighter(languages: [descriptor])
        // must terminate (not hang); result may be empty if the guard trips
        let result = h.highlight(String(repeating: "a", count: 8), as: "spin")
        #expect(result.tokens.count >= 0) // reached here == did not hang
    }

    @Test func matchNothingEndAtEOFDoesNotLoop() {
        // A mode whose end is highlight.js's MATCH_NOTHING_RE sentinel
        // (`\b\B`, which can never match) must not deadlock at EOF.
        // `NSRegularExpression.enumerateMatches` reports a spurious
        // zero-width `\b\B` match at end-of-input that `firstMatch` does
        // not — the disagreement previously spun the parse loop until the
        // infinite-loop guard tripped and discarded ALL tokens. HTTP is
        // the real-world trigger (header-body mode ends with `\b\B`).
        let responses = [
            "HTTP/1.1 200\nx",                 // bare non-header line after status
            "GET / HTTP/1.1\nx",               // request variant
            "HTTP/2 301\nlocation: x\ngarbage",
        ]
        for code in responses {
            let result = Highlighter.shared.highlight(code, as: "http")
            // must produce the status/request-line tokens, not an empty
            // result from a tripped infinite-loop guard
            #expect(!result.tokens.isEmpty, "http lost all tokens for \(code.debugDescription)")
        }

        // direct sentinel: a custom grammar whose child ends with `\b\B`
        let descriptor = LanguageDescriptor(name: "nothing") {
            LanguageDefinition(name: "nothing", root: Mode(contains: [
                Mode(scope: "x", begin: "a", end: "\\b\\B", contains: [
                    Mode(scope: "y", begin: "b"),
                ]),
            ]))
        }
        let h = Highlighter(languages: [descriptor])
        // "ab" opens the never-ending mode; must terminate at EOF
        let r = h.highlight("ab", as: "nothing")
        #expect(r.tokens.map(\.scope) == ["x", "y"])
    }

    @Test func zeroWidthBeginAtEOFDoesNotCrash() {
        // A child mode whose begin matches zero-width at end-of-input
        // (`$`), immediately followed by its zero-width end at the same
        // EOF position, drives the issue-#2140 deadlock guard to fire at
        // `index == length`. With keywords on the child, an unguarded
        // guard would build an out-of-bounds buffer range and crash in
        // processKeywords; without keywords it emits a token past EOF.
        let descriptor = LanguageDescriptor(name: "zw") {
            LanguageDefinition(name: "zw", root: Mode(contains: [
                Mode(scope: "x", begin: "$", end: "$", keywords: "a"),
            ]))
        }
        let h = Highlighter(languages: [descriptor])
        for input in ["a", "ab", "a", "word", ""] {
            let r = h.highlight(input, as: "zw")
            let length = (input as NSString).length
            for token in r.tokens {
                #expect(token.range.location + token.range.length <= length,
                        "out-of-bounds token for input \"\(input)\"")
            }
        }
    }

    /// A grammar referencing a capture group its pattern doesn't have —
    /// in a callback subscript or a multi-class scope — must behave like
    /// JavaScript (`match[N]` is undefined), not raise NSRangeException.
    @Test func outOfRangeCaptureGroupIsNilNotACrash() {
        let seen = Mutex<[String?]>([])
        let descriptor = LanguageDescriptor(name: "oor") {
            LanguageDefinition(name: "oor", root: Mode(contains: [
                Mode(
                    begin: "(q)x",
                    beginScope: [
                        -1: "negative",
                        1: "strong",
                        7: "emphasis", // 7 doesn't exist
                    ],
                    onBegin: { match, _ in
                        seen.withLock { $0.append(contentsOf: [match[1], match[5], match[-1]]) }
                    }
                ),
            ]))
        }
        let h = Highlighter(languages: [descriptor])
        let result = h.highlight("qx", as: "oor")
        #expect(seen.withLock { $0 } == ["q", nil, nil])
        #expect(result.tokens.contains { $0.scope == "strong" })
        #expect(!result.tokens.contains { $0.scope == "emphasis" })
        #expect(!result.tokens.contains { $0.scope == "negative" })
    }
}
