import Foundation
import Testing
@testable import HighlightKit

/// The compiler rejects malformed grammars with precise errors. These
/// guards protect callers who author custom grammars.
@Suite("Compiler validation")
struct CompilerValidationTests {
    private func compile(_ root: Mode) throws -> CompiledLanguage {
        try ModeCompiler.compile(LanguageDefinition(name: "v", root: root))
    }

    private func expectInvalidGrammar(_ root: Mode) {
        #expect(throws: HighlightError.self) { _ = try compile(root) }
    }

    @Test func multiPartBeginNeedsScopeMap() {
        expectInvalidGrammar(Mode(contains: [Mode(begin: ["a", "b"])]))
    }

    @Test func multiPartEndNeedsScopeMap() {
        expectInvalidGrammar(Mode(contains: [
            Mode(begin: "x", end: ["a", "b"]),
        ]))
    }

    @Test func multiPartBeginRejectsSkipFlags() {
        expectInvalidGrammar(Mode(contains: [
            Mode(begin: ["a", "b"], beginScope: [1: "x", 2: "y"], skip: true),
        ]))
        expectInvalidGrammar(Mode(contains: [
            Mode(begin: ["a", "b"], beginScope: [1: "x", 2: "y"], excludeBegin: true),
        ]))
    }

    @Test func multiPartEndRejectsSkipFlags() {
        expectInvalidGrammar(Mode(contains: [
            Mode(begin: "s", end: ["a", "b"], endScope: [1: "x", 2: "y"], excludeEnd: true),
        ]))
    }

    @Test func beforeMatchRejectsStarts() {
        let m = Mode(begin: "x", beforeMatch: "y", starts: Mode(begin: "z"))
        expectInvalidGrammar(Mode(contains: [m]))
    }

    @Test func matchAndBeginConflict() {
        expectInvalidGrammar(Mode(contains: [Mode(match: "a", begin: "b")]))
    }

    @Test func multiPartMatchWithScopeMapCompiles() throws {
        // valid multi-part match with a group scope map
        let compiled = try compile(Mode(contains: [
            Mode(scope: [1: "keyword", 2: "title"], match: ["(def)", "(\\w+)"]),
        ]))
        guard case .multi(let groups)? = compiled.root.contains[0].beginScope else {
            Issue.record("expected a multi begin scope")
            return
        }
        #expect(groups.map(\.scope) == ["keyword", "title"])
    }

    @Test func multiPartEndWithScopeMapCompiles() throws {
        let compiled = try compile(Mode(contains: [
            Mode(scope: "wrapper", begin: "start", end: ["(mid)", "(end)"], endScope: [1: "a", 2: "b"]),
        ]))
        guard case .multi = compiled.root.contains[0].endScope else {
            Issue.record("expected a multi end scope")
            return
        }
    }

    @Test func multiPartScopeWithNilGroupRunsKeywords() throws {
        // an unmapped group in a scope map is keyword-processed, not
        // scoped — exercise the emitter's nil-scope branch end to end
        let descriptor = LanguageDescriptor(name: "np") {
            LanguageDefinition(name: "np", root: Mode(
                keywords: "kw",
                contains: [Mode(begin: ["(#)", "(\\w+)"], beginScope: [1: "punctuation", 2: ""])]
            ))
        }
        let h = Highlighter(languages: [descriptor])
        let result = h.highlight("#kw", as: "np")
        // "#" → punctuation, "kw" → keyword (via the nil-scope group)
        #expect(result.tokens.contains { $0.scope == "punctuation" })
        #expect(result.tokens.contains { $0.scope == "keyword" })
    }
}
