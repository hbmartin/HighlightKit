import Foundation
import Testing
@testable import HighlightKit

@Suite("Token emitter")
struct TokenEmitterTests {
    @Test func plainTextEmitsNoTokens() {
        let emitter = TokenEmitter()
        emitter.addText(length: 5)
        #expect(emitter.tokens.isEmpty)
        #expect(emitter.cursor == 5)
    }

    @Test func scopedTextEmitsTokens() {
        let emitter = TokenEmitter()
        emitter.openScope("string")
        emitter.addText(length: 3)
        emitter.closeScope()
        #expect(emitter.tokens == [HighlightToken(range: NSRange(location: 0, length: 3), scopes: ["string"])])
    }

    @Test func adjacentIdenticalRunsMerge() {
        let emitter = TokenEmitter()
        emitter.openScope("string")
        emitter.addText(length: 3)
        emitter.addText(length: 2)
        emitter.closeScope()
        #expect(emitter.tokens.count == 1)
        #expect(emitter.tokens[0].range == NSRange(location: 0, length: 5))
    }

    @Test func differentScopesDoNotMerge() {
        let emitter = TokenEmitter()
        emitter.openScope("string")
        emitter.addText(length: 3)
        emitter.closeScope()
        emitter.openScope("keyword")
        emitter.addText(length: 2)
        emitter.closeScope()
        #expect(emitter.tokens.count == 2)
        #expect(emitter.tokens[1].scopes == ["keyword"])
    }

    @Test func keywordNestsUnderCurrentStack() {
        let emitter = TokenEmitter()
        emitter.openScope("string")
        emitter.addKeyword(length: 4, scope: "keyword")
        emitter.closeScope()
        #expect(emitter.tokens == [HighlightToken(range: NSRange(location: 0, length: 4), scopes: ["string", "keyword"])])
    }

    @Test func zeroLengthIsIgnored() {
        let emitter = TokenEmitter()
        emitter.openScope("x")
        emitter.addText(length: 0)
        emitter.addKeyword(length: 0, scope: "y")
        #expect(emitter.tokens.isEmpty)
        #expect(emitter.cursor == 0)
    }

    @Test func unbalancedCloseIsTolerated() {
        let emitter = TokenEmitter()
        emitter.closeScope() // no crash
        emitter.openScope("a")
        emitter.closeScope()
        emitter.closeScope() // extra
        emitter.addText(length: 2)
        #expect(emitter.tokens.isEmpty)
    }

    @Test func sublanguageSplicing() {
        let emitter = TokenEmitter()
        emitter.addText(length: 10) // plain prefix
        emitter.openScope("code")
        let sub = [
            HighlightToken(range: NSRange(location: 2, length: 3), scopes: ["keyword"]),
            HighlightToken(range: NSRange(location: 7, length: 1), scopes: ["number"]),
        ]
        emitter.addSublanguage(sub, length: 9)
        emitter.closeScope()

        #expect(emitter.tokens == [
            // gap [0,2) under outer scope
            HighlightToken(range: NSRange(location: 10, length: 2), scopes: ["code"]),
            HighlightToken(range: NSRange(location: 12, length: 3), scopes: ["code", "keyword"]),
            HighlightToken(range: NSRange(location: 15, length: 2), scopes: ["code"]),
            HighlightToken(range: NSRange(location: 17, length: 1), scopes: ["code", "number"]),
            HighlightToken(range: NSRange(location: 18, length: 1), scopes: ["code"]),
        ])
        #expect(emitter.cursor == 19)
    }

    @Test func sublanguageWithEmptyOuterStackDropsGaps() {
        let emitter = TokenEmitter()
        let sub = [HighlightToken(range: NSRange(location: 1, length: 2), scopes: ["keyword"])]
        emitter.addSublanguage(sub, length: 5)
        #expect(emitter.tokens == [HighlightToken(range: NSRange(location: 1, length: 2), scopes: ["keyword"])])
        #expect(emitter.cursor == 5)
    }
}
