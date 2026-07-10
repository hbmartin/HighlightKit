import Foundation
import Testing
@testable import HighlightKit

@Suite("Keyword compilation")
struct KeywordCompilerTests {
    @Test func stringLiteralKeywords() {
        let compiled = KeywordCompiler.compile("for while do", caseInsensitive: false)
        #expect(compiled["for"]?.scope == "keyword")
        #expect(compiled["while"]?.scope == "keyword")
        #expect(compiled.count == 3)
    }

    @Test func commonKeywordsGetZeroRelevance() {
        let compiled = KeywordCompiler.compile("for banana", caseInsensitive: false)
        #expect(compiled["for"]?.relevance == 0)   // common word
        #expect(compiled["banana"]?.relevance == 1)
    }

    @Test func explicitRelevance() {
        let compiled = KeywordCompiler.compile("unless|10 if|1", caseInsensitive: false)
        #expect(compiled["unless"]?.relevance == 10)
        #expect(compiled["if"]?.relevance == 1) // explicit beats common-word zero
    }

    @Test func groupedKeywords() {
        let keywords: Keywords = [
            "keyword": "if else",
            "literal": ["true", "false"],
            "built_in": "print",
        ]
        let compiled = KeywordCompiler.compile(keywords, caseInsensitive: false)
        #expect(compiled["if"]?.scope == "keyword")
        #expect(compiled["true"]?.scope == "literal")
        #expect(compiled["print"]?.scope == "built_in")
    }

    @Test func caseInsensitiveLowercasesWords() {
        let compiled = KeywordCompiler.compile("SELECT", caseInsensitive: true)
        #expect(compiled["select"] != nil)
        #expect(compiled["SELECT"] == nil)
    }

    @Test func keywordsPattern() {
        let keywords = Keywords(pattern: "[a-z-]+", ["keyword": "foo-bar"])
        #expect(keywords.pattern == "[a-z-]+")
        #expect(keywords.groups["keyword"]?.words == ["foo-bar"])
    }
}
