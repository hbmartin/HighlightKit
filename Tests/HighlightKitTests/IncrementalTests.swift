import Foundation
import Testing
@testable import HighlightKit

/// The incremental / block-editor highlighting contract: continuations
/// thread parser state across lines and compare equal when the end-state
/// converges, so an editor can bound cascading re-highlight work.
@Suite("Incremental highlighting")
struct IncrementalTests {
    private func singleCSSSubLanguageHighlighter() -> Highlighter {
        let host = LanguageDescriptor(name: "css-host") {
            LanguageDefinition(
                name: "css-host",
                root: Mode(contains: [
                    Mode(begin: "<style>", end: "</style>", subLanguage: ["css"]),
                ])
            )
        }
        let css = LanguageCatalog.all.first { $0.name == "css" }!
        return Highlighter(languages: [host, css])
    }

    private func frameScopedSubLanguageHighlighter() -> Highlighter {
        let inner = LanguageDescriptor(name: "inner") {
            LanguageDefinition(
                name: "inner",
                root: Mode(contains: [
                    Mode(scope: "comment", begin: #"/\*"#, end: #"\*/"#),
                ])
            )
        }
        let host = LanguageDescriptor(name: "sub-host") {
            LanguageDefinition(
                name: "sub-host",
                root: Mode(contains: [
                    Mode(begin: "<", end: ">", subLanguage: ["inner"]),
                ])
            )
        }
        return Highlighter(languages: [host, inner])
    }

    /// Re-highlighting a line with the same preceding state yields an
    /// equal end continuation — the signal an editor uses to stop.
    @Test func continuationConvergence() {
        let h = Highlighter.shared
        // a plain line in the default (top-level) state
        let a = h.highlight("let x = 1\n", as: "swift")
        let b = h.highlight("let y = 2\n", as: "swift")
        // both end in the same (root) state
        #expect(a.continuation == b.continuation)
    }

    @Test func continuationDivergesInsideComment() {
        let h = Highlighter.shared
        // a line that opens a block comment ends in a different state
        let plain = h.highlight("let x = 1\n", as: "swift")
        let opensComment = h.highlight("let x = 1 /* open\n", as: "swift")
        #expect(plain.continuation != opensComment.continuation)
    }

    @Test func heredocDelimiterParticipatesInConvergence() {
        let h = Highlighter.shared
        let eof = h.highlight("cat <<EOF\n", as: "bash")
        let tag = h.highlight("cat <<TAG\n", as: "bash")

        // The compiled mode stack is identical, but the callback data
        // determines which future line closes the heredoc.
        #expect(eof.continuation != tag.continuation)
    }

    @Test func embeddedLanguageStateParticipatesInConvergence() {
        let h = singleCSSSubLanguageHighlighter()
        let style = h.highlight("<style>\n", as: "css-host").continuation
        let comment = h.highlight("/* open\n", as: "css-host", continuation: style)
        let plain = h.highlight("a { color: red }\n", as: "css-host", continuation: style)

        // Both outer XML stacks are inside the same <style> mode; only the
        // nested CSS continuation distinguishes an open comment.
        #expect(comment.continuation != plain.continuation)
    }

    @Test func oneContinuationCanBeForkedWithoutStatePollution() {
        let descriptor = LanguageDescriptor(name: "fork-state") {
            let heredoc = Mode(
                scope: "string", begin: #"<<([A-Z]+)"#,
                end: #"([A-Z]+)"#, endSameAsBegin: true
            )
            return LanguageDefinition(name: "fork-state", root: Mode(contains: [heredoc]))
        }
        let h = Highlighter(languages: [descriptor])
        let original = h.highlight("<<EOF\n", as: "fork-state").continuation
        let expected = h.highlight("EOF\n", as: "fork-state", continuation: original)

        // This branch closes EOF and opens the same compiled mode with a
        // different delimiter. It must mutate only its own Run snapshot.
        _ = h.highlight("EOF\n<<TAG\n", as: "fork-state", continuation: original)
        let actual = h.highlight("EOF\n", as: "fork-state", continuation: original)

        #expect(actual.tokens == expected.tokens)
        #expect(actual.continuation == expected.continuation)
    }

    @Test func recursiveCallbackStateIsPerActivation() {
        let descriptor = LanguageDescriptor(name: "nested-delimiters") {
            let nested = Mode(
                scope: "string", begin: #"<([A-Z])>"#,
                end: #"</([A-Z])>"#, endSameAsBegin: true
            )
            nested.contains = [Mode.selfReference]
            return LanguageDefinition(
                name: "nested-delimiters", root: Mode(contains: [nested])
            )
        }
        let h = Highlighter(languages: [descriptor])
        var continuation: Continuation?
        for line in ["<A>", "<B>", "</B>", "</A>"] {
            continuation = h.highlight(
                line + "\n", as: "nested-delimiters", continuation: continuation
            ).continuation
        }
        let fresh = h.highlight("plain\n", as: "nested-delimiters").continuation
        #expect(continuation == fresh)
    }

    @Test func vetoedBeginDoesNotPolluteContinuation() {
        let descriptor = LanguageDescriptor(name: "veto-state") {
            let vetoed = Mode(begin: "x", onBegin: { _, response in
                response.data["attempt"] = "x"
                response.ignoreMatch()
            })
            return LanguageDefinition(
                name: "veto-state", root: Mode(contains: [vetoed])
            )
        }
        let h = Highlighter(languages: [descriptor])
        let vetoed = h.highlight("x", as: "veto-state").continuation
        let fresh = h.highlight("", as: "veto-state").continuation
        #expect(vetoed == fresh)
    }

    @Test func keywordRelevanceStateParticipatesInEquality() {
        let h = Highlighter.shared
        let one = h.highlight("let a = 1\n", as: "swift").continuation
        let saturated = h.highlight(
            String(repeating: "let a = 1; ", count: HighlightEngine.maxKeywordHits + 1),
            as: "swift"
        ).continuation
        #expect(one != saturated)
    }

    @Test func saturatedKeywordCountsConverge() {
        let h = Highlighter.shared
        let seven = h.highlight(
            String(repeating: "let ", count: HighlightEngine.maxKeywordHits),
            as: "swift"
        )
        let eight = h.highlight(
            String(repeating: "let ", count: HighlightEngine.maxKeywordHits + 1),
            as: "swift"
        )

        // Once a keyword reaches the relevance cap, additional hits cannot
        // affect any future token or relevance output. The stored state must
        // saturate too, otherwise incremental re-highlighting never
        // converges on keyword-dense lines.
        #expect(seven.continuation == eight.continuation)
    }

    @Test func closedSubLanguageFrameDoesNotLeakNestedState() {
        let h = frameScopedSubLanguageHighlighter()
        // The inner comment remains open when this host frame closes.
        let closed = h.highlight("</*>", as: "sub-host")
        let continued = h.highlight(
            "<x>", as: "sub-host", continuation: closed.continuation
        )
        let fresh = h.highlight("<x>", as: "sub-host")

        #expect(continued.tokens == fresh.tokens)
        #expect(continued.relevance == fresh.relevance)
        #expect(continued.continuation == fresh.continuation)
    }

    @Test func foreignContinuationStartsFromFreshState() {
        let h = Highlighter.shared
        let javascript = h.highlight("/* open\n", as: "javascript").continuation
        let expected = h.highlight("let x = 1\n", as: "swift")
        let actual = h.highlight("let x = 1\n", as: "swift", continuation: javascript)

        #expect(actual.tokens == expected.tokens)
        #expect(actual.relevance == expected.relevance)
        #expect(actual.continuation == expected.continuation)

        // A complex grammar's matcher slots must never be used with a
        // smaller grammar cache (the old implementation could trap here).
        let plain = h.highlight("text", as: "plaintext", continuation: javascript)
        #expect(plain.tokens.isEmpty)
    }

    @Test func continuationFromAnotherHighlighterStartsFresh() {
        let first = Highlighter()
        let second = Highlighter()
        let foreign = first.highlight("/* open\n", as: "javascript").continuation
        let expected = second.highlight("const x = 1\n", as: "javascript")
        let actual = second.highlight("const x = 1\n", as: "javascript", continuation: foreign)

        #expect(actual.tokens == expected.tokens)
        #expect(actual.continuation == expected.continuation)
    }

    /// The canonical editor loop: highlight line-by-line, and when a
    /// changed line's end-state matches what was stored, following lines
    /// are provably unaffected.
    @Test func editorConvergenceLoop() {
        let h = Highlighter.shared
        let lines = ["func f() {", "    let x = 1", "    return x", "}"]

        // initial full pass — record each line's end continuation
        var endStates: [Continuation?] = []
        var cont: Continuation?
        for line in lines {
            let r = h.highlight(line + "\n", as: "swift", continuation: cont)
            cont = r.continuation
            endStates.append(cont)
        }

        // edit line 1 (index 1) without changing its end-state (still
        // top-of-body). Re-highlight from the stored state before it.
        let before = endStates[0]
        let edited = h.highlight("    let y = 99\n", as: "swift", continuation: before)
        // its end-state converges with the original → no cascade needed
        #expect(edited.continuation == endStates[1])
    }

    /// Whole-string vs. line-by-line highlighting assign the same
    /// innermost scope to every character offset — the true fidelity
    /// invariant (tokens split at line boundaries incrementally, but the
    /// per-character scoping must be identical).
    /// For text without cross-line regex context (open comment carrying
    /// state across lines, then plain statements), line-by-line
    /// highlighting reproduces whole-string per-character scoping exactly
    /// — the continuation carries the mode stack correctly. (Constructs
    /// with multi-line regex lookahead are covered by
    /// `continuationCarriesHeredocState` and documented as intrinsic
    /// line-isolation differences; see `Continuation`.)
    @Test func incrementalMatchesWholeString() {
        let source = "/* doc\n comment */\nlet x = 42\nlet y = x + 1\n"
        let length = (source as NSString).length

        func scopeMap(_ tokens: [HighlightToken], base: Int = 0) -> [Int: String] {
            var map: [Int: String] = [:]
            for token in tokens {
                for i in 0..<token.range.length {
                    map[base + token.range.location + i] = token.scope
                }
            }
            return map
        }

        let whole = scopeMap(Highlighter.shared.highlight(source, as: "swift").tokens)

        var incremental: [Int: String] = [:]
        var cont: Continuation?
        var base = 0
        for line in source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let text = line + "\n"
            let r = Highlighter.shared.highlight(text, as: "swift", continuation: cont)
            cont = r.continuation
            incremental.merge(scopeMap(r.tokens, base: base)) { _, new in new }
            base += (text as NSString).length
        }

        for offset in 0..<length {
            #expect(whole[offset] == incremental[offset], "scope mismatch at offset \(offset)")
        }
    }

    @Test func continuationSelfEqual() {
        let r = Highlighter.shared.highlight("/* x\n", as: "javascript")
        #expect(r.continuation == r.continuation)
    }

    /// The continuation carries heredoc `endSameAsBegin` state (stored in
    /// callback data) across lines: a bash heredoc opened on one line must
    /// stay a string until its delimiter recurs on a later line — exactly
    /// as whole-string highlighting scopes it.
    @Test func continuationCarriesHeredocState() {
        let lines = ["cat <<EOF", "line one", "line two", "EOF", "echo done"]
        let whole = Highlighter.shared.highlight(lines.joined(separator: "\n") + "\n", as: "bash")
        let wholeNS = (lines.joined(separator: "\n") + "\n") as NSString

        var cont: Continuation?
        var base = 0
        var incrementalString: [Int: Bool] = [:]
        for line in lines {
            let text = line + "\n"
            let r = Highlighter.shared.highlight(text, as: "bash", continuation: cont)
            cont = r.continuation
            let ns = text as NSString
            for t in r.tokens where t.scope == "string" {
                for i in 0..<t.range.length { incrementalString[base + t.range.location + i] = true }
            }
            base += ns.length
        }
        // the heredoc body ("line one", "line two") is `string` in both
        for t in whole.tokens where t.scope == "string" {
            let sample = t.range.location + t.range.length / 2
            #expect(incrementalString[sample] == true,
                    "heredoc string lost across lines at \(sample): \(wholeNS.substring(with: t.range).debugDescription)")
        }
    }

    /// The continuation carries embedded sub-language state: a `<style>`
    /// block opened in one XML line keeps highlighting CSS on the next.
    @Test func continuationCarriesSubLanguageState() {
        let lines = ["<style>", "a { color: red; }", "</style>"]
        var cont: Continuation?
        var sawCSSScope = false
        for line in lines {
            let r = Highlighter.shared.highlight(line + "\n", as: "xml", continuation: cont)
            cont = r.continuation
            // the CSS line should carry attribute/selector scopes from the
            // embedded css grammar, not be plain xml text
            if line.contains("color"), r.tokens.contains(where: { $0.scope == "attribute" || $0.scope == "selector-tag" }) {
                sawCSSScope = true
            }
        }
        #expect(sawCSSScope, "embedded CSS not highlighted across lines")
    }

    @Test func continuationCarriesCompleteNestedLanguageState() {
        let h = singleCSSSubLanguageHighlighter()
        let lines = ["<style>", "/* open", "still a comment", "*/", "</style>"]
        var continuation: Continuation?
        var middle: HighlightResult?
        for line in lines {
            let result = h.highlight(
                line + "\n", as: "css-host", continuation: continuation
            )
            continuation = result.continuation
            if line == "still a comment" { middle = result }
        }
        #expect(middle?.tokens.contains(where: { $0.scope == "comment" }) == true)
    }
}
