import Foundation
import Testing
@testable import HighlightKit

/// Direct coverage for reusable helpers and literal-syntax initializers
/// that grammars can use but the bundled ones happen not to exercise.
@Suite("Helper coverage")
struct HelperCoverageTests {
    @Test func commonModeHelpersAreUsable() throws {
        // methodGuard, phrasalWordsMode, titleMode, numberMode etc. are
        // public API — a custom grammar must be able to compile with them
        let descriptor = LanguageDescriptor(name: "helpers") {
            LanguageDefinition(name: "helpers", root: Mode(contains: [
                CommonModes.methodGuard,
                CommonModes.phrasalWordsMode,
                CommonModes.titleMode,
                CommonModes.underscoreTitleMode,
                CommonModes.numberMode,
                CommonModes.binaryNumberMode,
                CommonModes.hashCommentMode,
                CommonModes.regexpMode,
            ]))
        }
        let h = Highlighter(languages: [descriptor])
        let result = h.highlight("foo 42 0b101 # note\n", as: "helpers")
        #expect(result.tokens.contains { $0.scope == "number" })
        #expect(result.tokens.contains { $0.scope == "comment" })
    }

    @Test func shebangWithBinary() {
        let descriptor = LanguageDescriptor(name: "sh") {
            LanguageDefinition(name: "sh", root: Mode(contains: [
                CommonModes.shebang(binary: "python", relevance: 10),
            ]))
        }
        let h = Highlighter(languages: [descriptor])
        let result = h.highlight("#!/usr/bin/env python\ncode", as: "sh")
        #expect(result.tokens.first?.scope == "meta")
        // shebang must only match at offset 0
        let notFirst = h.highlight("x\n#!/usr/bin/env python", as: "sh")
        #expect(notFirst.tokens.isEmpty)
    }

    @Test func keywordsExpressibleByArrayLiteral() {
        let keywords: Keywords = ["for", "while", "do"]
        let compiled = KeywordCompiler.compile(keywords, caseInsensitive: false)
        #expect(compiled["for"]?.scope == "keyword")
        #expect(compiled["while"] != nil)
        #expect(compiled["do"] != nil)
    }

    @Test func keywordsGroupArrayLiteral() {
        let group: Keywords.Group = ["a", "b", "c"]
        #expect(group.words == ["a", "b", "c"])
    }

    @Test func regexSourceEitherArrayForm() {
        #expect(RegexSource.either(["a", "b", "c"], capture: true) == "(a|b|c)")
    }

    @Test func tokenEmitterEmptySublanguageStack() {
        // addSublanguage with an empty outer stack: gaps drop, tokens keep
        let emitter = TokenEmitter()
        let sub = [
            HighlightToken(range: NSRange(location: 0, length: 2), scopes: ["keyword"]),
            HighlightToken(range: NSRange(location: 5, length: 1), scopes: ["number"]),
        ]
        emitter.addSublanguage(sub, length: 8)
        #expect(emitter.tokens.count == 2)
        #expect(emitter.cursor == 8)
    }

    @Test func continuationIsSendable() async {
        // the continuation must be safe to hand across isolation domains
        // (the block editor stores it per line off the main actor)
        let first = Highlighter.shared.highlight("/* open\n", as: "javascript")
        let cont = first.continuation
        let count = await Task.detached { () -> Int in
            Highlighter.shared.highlight("still */ x\n", as: "javascript", continuation: cont).tokens.count
        }.value
        #expect(count >= 0)
    }
}
