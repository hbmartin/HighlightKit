import Foundation
import Testing
@testable import HighlightKit

/// Unit coverage for the matcher prefilters. These paths are also
/// exercised end-to-end by the fidelity suite; the cases here pin the
/// tricky boundaries directly.
@Suite("Matcher prefilters")
struct PrefilterTests {
    private func highlighter(_ makeModes: @escaping @Sendable () -> [Mode]) -> Highlighter {
        let descriptor = LanguageDescriptor(name: "pf-test") {
            LanguageDefinition(name: "pf-test", root: Mode(contains: makeModes()))
        }
        return Highlighter(languages: [descriptor])
    }

    @Test func dotOptionalLiteralMatchesAtBothOffsets() {
        let h = highlighter { [Mode(scope: "x", begin: ".?html`", end: "`")] }
        // offset 1: previous char consumed by `.`
        let r1 = h.highlight("zhtml` a `", as: "pf-test")
        #expect(r1.tokens.first?.range.location == 0)
        // offset 0 at start of input (`.` matches nothing)
        let r2 = h.highlight("html` a `", as: "pf-test")
        #expect(r2.tokens.first?.range.location == 0)
        // `.` must not cross a newline
        let r3 = h.highlight("z\nhtml` a `", as: "pf-test")
        #expect(r3.tokens.first?.range.location == 2)
    }

    @Test func doctagLiteralBacksUpOverSpaces() {
        let code = "// x   TODO: fix it\n"
        let result = Highlighter.shared.highlight(code, as: "javascript")
        let ns = code as NSString
        let doctag = result.tokens.first { $0.scope == "doctag" }
        #expect(doctag != nil)
        if let doctag {
            #expect(ns.substring(with: doctag.range) == "TODO:")
        }
    }

    @Test func proseGateStillMatchesRealProse() {
        // three english words inside a comment boost relevance via the
        // prose mode — compare against a symbols-only comment
        let prose = Highlighter.shared.highlight("// this is a comment with words\n", as: "javascript")
        let symbols = Highlighter.shared.highlight("// @#$%^&*\n", as: "javascript")
        #expect(prose.relevance > symbols.relevance)
    }

    @Test func sparseHeadFindsPunctuationRules() {
        let h = highlighter { [Mode(scope: "tick", begin: "`[a-z]+`")] }
        let code = "aaa `bb` ccc `dd`"
        let result = h.highlight(code, as: "pf-test")
        #expect(result.tokens.count == 2)
        #expect(result.tokens.map(\.range) == [
            NSRange(location: 4, length: 4),
            NSRange(location: 13, length: 4),
        ])
    }

    /// A rule vetoed at one position then re-queried one position later
    /// lands inside the previous cached match — the overlap fallback
    /// must find overlapping matches the non-overlapping sequence lacks.
    @Test func overlappingMatchesAfterVeto() {
        let h = highlighter {
            [Mode(
                scope: "aa",
                begin: "aa",
                onBegin: { match, response in
                    // veto only the very first occurrence
                    if match.index == 0 { response.ignoreMatch() }
                }
            )]
        }
        // "aaa": vetoed at 0; rescan from 1 must find the overlapping "aa"
        let result = h.highlight("aaa", as: "pf-test")
        #expect(result.tokens == [HighlightToken(range: NSRange(location: 1, length: 2), scopes: ["aa"])])
    }

    @Test func dotOptionalLiteralWithEscapes() {
        // a `.?` template whose literal contains an escaped tab and an
        // escaped punctuation char exercises decodeLiteral's escape arms
        let h = highlighter { [Mode(scope: "x", begin: ".?a\\tb\\.c", end: "z")] }
        let result = h.highlight("qa\tb.cz", as: "pf-test")
        #expect(result.tokens.first?.scope == "x")
    }

    @Test func dotOptionalLiteralRejectsMetacharacters() {
        // `.?a+` is not a pure literal after `.?` → falls back to no
        // literal prefilter but must still highlight correctly
        let h = highlighter { [Mode(scope: "x", begin: ".?a+", end: "z")] }
        let result = h.highlight("qaaaz", as: "pf-test")
        #expect(result.tokens.first?.scope == "x")
    }

    @Test func multiPartEndScopeEmitsPerGroup() {
        // end: [parts] with a group scope map exercises the endScope
        // multi-class emission path end to end
        let descriptor = LanguageDescriptor(name: "me") {
            LanguageDefinition(name: "me", root: Mode(contains: [
                Mode(
                    scope: "wrapper",
                    begin: "<",
                    end: ["(--)", "(>)"],
                    endScope: [1: "keyword", 2: "punctuation"]
                ),
            ]))
        }
        let h = Highlighter(languages: [descriptor])
        let result = h.highlight("<abc-->", as: "me")
        let scopes = result.tokens.map(\.scope)
        #expect(scopes.contains("keyword"))
        #expect(scopes.contains("punctuation"))
    }
}
