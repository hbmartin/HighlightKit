import Foundation
import Testing
@testable import HighlightKit

@Suite("Engine smoke tests")
struct EngineSmokeTests {
    @Test func jsonBasics() throws {
        let code = #"{"name": "value", "n": 42, "ok": true}"#
        let result = Highlighter.shared.highlight(code, as: "json")
        #expect(result.language == "json")
        #expect(!result.tokens.isEmpty)

        let ns = code as NSString
        let texts = result.tokens.map { ns.substring(with: $0.range) }
        let scopes = result.tokens.map(\.scope)
        #expect(texts.contains(#""name""#))
        #expect(scopes.contains("attr"))
        #expect(scopes.contains("number"))
        // `true` nests keyword processing inside the literal mode,
        // exactly like highlight.js (scopes = [literal, keyword])
        #expect(result.tokens.contains { $0.scopes == ["literal", "keyword"] })
    }

    @Test func plaintextHasNoTokens() {
        let result = Highlighter.shared.highlight("hello world", as: "plaintext")
        #expect(result.tokens.isEmpty)
        #expect(result.language == "plaintext")
    }

    @Test func xmlBasics() {
        let code = #"<a href="https://example.com">link</a>"#
        let result = Highlighter.shared.highlight(code, as: "xml")
        let scopes = result.tokens.map(\.scope)
        #expect(scopes.contains("name"))
        #expect(scopes.contains("attr"))
        #expect(scopes.contains("string"))
    }

    @Test func tokensCoverOnlyValidRanges() {
        let code = "{\"a\": [1, 2, null]}"
        let result = Highlighter.shared.highlight(code, as: "json")
        let length = (code as NSString).length
        var previousEnd = 0
        for token in result.tokens {
            #expect(token.range.location >= previousEnd)
            #expect(token.range.location + token.range.length <= length)
            previousEnd = token.range.location
        }
    }
}
