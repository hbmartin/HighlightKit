import Foundation
import Testing
@testable import HighlightKit

/// Targets specific reachable branches that the corpus/fuzz suites don't
/// happen to exercise, so behavior at those edges is pinned directly.
@Suite("Branch coverage")
struct BranchCoverageTests {
    // MARK: illegal `$` zero-width handler (not at EOF)

    @Test func illegalDollarMidText() {
        // `illegal: $` matches zero-width at each line end. With illegals
        // ignored it must step over the newline, not stall — exercising
        // the mid-text zero-width illegal branch.
        let descriptor = LanguageDescriptor(name: "ild") {
            LanguageDefinition(name: "ild", root: Mode(
                illegal: ["$"],
                contains: [Mode(scope: "w", begin: "[a-z]+")]
            ))
        }
        let h = Highlighter(languages: [descriptor])
        let result = h.highlight("ab\ncd\nef", as: "ild") // ignoreIllegals defaults true
        // words on each line still highlighted; no hang, ranges in bounds
        let length = ("ab\ncd\nef" as NSString).length
        #expect(result.tokens.allSatisfy { $0.range.location + $0.range.length <= length })
        #expect(result.tokens.contains { $0.scope == "w" })
    }

    // MARK: endSameAsBegin onEnd mismatch (ignoreMatch)

    @Test func endSameAsBeginMismatchIgnored() {
        // A heredoc-style mode: only the exact opening token closes it.
        // A near-miss delimiter must be ignored (the onEnd callback calls
        // ignoreMatch), so the body keeps going until the real delimiter.
        let descriptor = LanguageDescriptor(name: "hd") {
            LanguageDefinition(name: "hd", root: Mode(contains: [
                Mode(
                    scope: "string",
                    begin: "<<(\\w+)",
                    end: "(\\w+)",
                    endSameAsBegin: true
                ),
            ]))
        }
        let h = Highlighter(languages: [descriptor])
        // opens with EOF; EOX is a near-miss (ignored); EOF closes it
        let code = "<<EOF body EOX more EOF tail"
        let result = h.highlight(code, as: "hd")
        let ns = code as NSString
        // the string token must span from `<<EOF` through the closing `EOF`
        // (i.e. include the near-miss EOX), not stop early
        let strings = result.tokens.filter { $0.scope == "string" }
        #expect(strings.contains { ns.substring(with: $0.range).contains("EOX") })
    }

    // MARK: beforeMatch validation

    @Test func beforeMatchRequiresSinglePatternBegin() {
        // beforeMatch itself must be a single pattern (a multi-part
        // beforeMatch is rejected at compile time).
        let partsBeforeMatch = Mode(begin: "x", beforeMatch: ["a", "b"])
        #expect(throws: HighlightError.self) {
            _ = try ModeCompiler.compile(LanguageDefinition(name: "bm1", root: Mode(contains: [partsBeforeMatch])))
        }
        // …and requires a (single-pattern) begin to attach to.
        let noBegin = Mode(beforeMatch: "a")
        #expect(throws: HighlightError.self) {
            _ = try ModeCompiler.compile(LanguageDefinition(name: "bm2", root: Mode(contains: [noBegin])))
        }
    }

    // MARK: non-monotonic / overlap cache queries (oneOffSearch)

    @Test func nonMonotonicVetoQueries() {
        // Multiple modes vetoing at overlapping positions force the cache
        // onto its oneOffSearch fallback paths repeatedly.
        let descriptor = LanguageDescriptor(name: "ov") {
            LanguageDefinition(name: "ov", root: Mode(contains: [
                Mode(scope: "a", begin: "aa", onBegin: { m, r in if m.index % 2 == 0 { r.ignoreMatch() } }),
                Mode(scope: "b", begin: "a"),
            ]))
        }
        let h = Highlighter(languages: [descriptor])
        let result = h.highlight("aaaaa", as: "ov")
        // must terminate and cover only valid ranges
        let length = 5
        var prev = 0
        for t in result.tokens {
            #expect(t.range.location >= prev)
            #expect(t.range.location + t.range.length <= length)
            prev = t.range.location
        }
    }

    // MARK: HighlightError descriptions

    @Test func errorDescriptions() {
        #expect(HighlightError.unknownLanguage("zz").description.contains("zz"))
        let bad = HighlightError.invalidGrammar(language: "g", reason: "why")
        #expect(bad.description.contains("g") && bad.description.contains("why"))
        // trigger a real invalid-regex error and read its description
        do {
            _ = try ModeCompiler.compile(LanguageDefinition(name: "ir", root: Mode(contains: [Mode(begin: "(")])))
            Issue.record("expected invalid regex")
        } catch let e as HighlightError {
            #expect(e.description.contains("ir"))
        } catch {
            Issue.record("wrong error")
        }
    }
}
