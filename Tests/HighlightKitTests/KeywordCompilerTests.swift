import Foundation
import Testing
@testable import HighlightKit

@Suite("Keyword compilation")
struct KeywordCompilerTests {
    /// Compiles with a throwaway hit-index namespace (single mode).
    private static func compile(
        _ keywords: Keywords, caseInsensitive: Bool
    ) -> CompiledKeywords {
        var hitIndices: [String: Int32] = [:]
        return KeywordCompiler.compile(
            keywords, caseInsensitive: caseInsensitive, hitIndices: &hitIndices
        )
    }

    @Test func stringLiteralKeywords() {
        let compiled = Self.compile("for while do", caseInsensitive: false)
        #expect(compiled["for"]?.scope == "keyword")
        #expect(compiled["while"]?.scope == "keyword")
        #expect(compiled.count == 3)
    }

    @Test func commonKeywordsGetZeroRelevance() {
        let compiled = Self.compile("for banana", caseInsensitive: false)
        #expect(compiled["for"]?.relevance == 0)   // common word
        #expect(compiled["banana"]?.relevance == 1)
    }

    @Test func explicitRelevance() {
        let compiled = Self.compile("unless|10 if|1", caseInsensitive: false)
        #expect(compiled["unless"]?.relevance == 10)
        #expect(compiled["if"]?.relevance == 1) // explicit beats common-word zero
    }

    @Test func groupedKeywords() {
        let keywords: Keywords = [
            "keyword": "if else",
            "literal": ["true", "false"],
            "built_in": "print",
        ]
        let compiled = Self.compile(keywords, caseInsensitive: false)
        #expect(compiled["if"]?.scope == "keyword")
        #expect(compiled["true"]?.scope == "literal")
        #expect(compiled["print"]?.scope == "built_in")
    }

    @Test func caseInsensitiveLowercasesWords() {
        let compiled = Self.compile("SELECT", caseInsensitive: true)
        #expect(compiled["select"] != nil)
        #expect(compiled["SELECT"] == nil)
    }

    @Test func keywordsPattern() {
        let keywords = Keywords(pattern: "[a-z-]+", ["keyword": "foo-bar"])
        #expect(keywords.pattern == "[a-z-]+")
        #expect(keywords.groups["keyword"]?.words == ["foo-bar"])
    }

    @Test func hitIndicesAreSharedPerWordAcrossModes() {
        var hitIndices: [String: Int32] = [:]
        let first = KeywordCompiler.compile(
            "return other", caseInsensitive: false, hitIndices: &hitIndices
        )
        let second = KeywordCompiler.compile(
            ["literal": "return"], caseInsensitive: false, hitIndices: &hitIndices
        )
        // Same word text → same saturation counter, exactly as
        // highlight.js counts hits per word per run.
        #expect(first["return"]?.hitIndex == second["return"]?.hitIndex)
        #expect(first["other"]?.hitIndex != first["return"]?.hitIndex)
        #expect(hitIndices.count == 2)
    }

    @Test func zeroRelevanceWordsAllocateNoCounter() {
        var hitIndices: [String: Int32] = [:]
        let compiled = KeywordCompiler.compile(
            "for banana", caseInsensitive: false, hitIndices: &hitIndices
        )
        #expect(compiled["for"]?.hitIndex == -1)   // common word, relevance 0
        #expect(compiled["banana"]?.hitIndex == 0)
        #expect(hitIndices.count == 1)
    }

    @Test func unitLookupMatchesStringSubscript() {
        let compiled = Self.compile("for banana état", caseInsensitive: false)
        for word in ["for", "banana", "état", "missing", "bananax", "fo"] {
            let units = Array(word.utf16)
            let direct = compiled.lookup(in: units, location: 0, length: units.count)
            #expect(direct?.scope == compiled[word]?.scope, Comment(rawValue: word))
            #expect(direct?.hitIndex == compiled[word]?.hitIndex, Comment(rawValue: word))
        }
    }

    @Test func foldingLookupFoldsOnlyASCII() {
        let compiled = Self.compile("SELECT Değer", caseInsensitive: true)
        let select = Array("SeLeCt".utf16)
        guard case .found(let entry) = compiled.lookupFoldingASCII(
            in: select, location: 0, length: select.count
        ) else {
            Issue.record("folded ASCII word must be found")
            return
        }
        #expect(entry.scope == "keyword")

        let missing = Array("selec".utf16)
        guard case .missing = compiled.lookupFoldingASCII(
            in: missing, location: 0, length: missing.count
        ) else {
            Issue.record("shorter word must be a plain miss")
            return
        }

        // A non-ASCII unit (here U+212A KELVIN SIGN, which Unicode-folds
        // to `k`) cannot be decided by ASCII folding — the caller must
        // take the String path, where `lowercased()` applies.
        let kelvin = Array("\u{212A}elvin".utf16)
        guard case .nonASCII = compiled.lookupFoldingASCII(
            in: kelvin, location: 0, length: kelvin.count
        ) else {
            Issue.record("non-ASCII words must route to the String path")
            return
        }
        #expect(compiled["değer"] != nil) // String path decides folded keys
    }

    @Test func unitLookupUsesSubrangeOfALargerBuffer() {
        let compiled = Self.compile("mid", caseInsensitive: false)
        let units = Array("xxmidyy".utf16)
        #expect(compiled.lookup(in: units, location: 2, length: 3) != nil)
        #expect(compiled.lookup(in: units, location: 1, length: 3) == nil)
        #expect(compiled.lookup(in: units, location: 2, length: 4) == nil)
    }

    /// Case-sensitive identity is UTF-16 code-unit exact — highlight.js's
    /// JavaScript object-lookup semantics. Swift `String` canonical
    /// equivalence (NFC key matching NFD input) was an accidental
    /// divergence from upstream; pin the faithful behavior.
    @Test func caseSensitiveKeywordsAreCodeUnitExact() {
        let nfcKey = "caf\u{E9}"           // é precomposed
        let nfdWord = "cafe\u{301}"        // e + combining acute
        #expect(nfcKey == nfdWord)          // canonically equal Strings…
        let compiled = Self.compile(Keywords(keyword: .init(words: [nfcKey])), caseInsensitive: false)
        let nfd = Array(nfdWord.utf16)
        // …but distinct code units must not match, exactly as in hljs.
        #expect(compiled.lookup(in: nfd, location: 0, length: nfd.count) == nil)
        let nfc = Array(nfcKey.utf16)
        #expect(compiled.lookup(in: nfc, location: 0, length: nfc.count) != nil)
    }

    /// A word listed under two scope groups resolves deterministically
    /// (sorted scope order — see FIDELITY.md on duplicate resolution).
    @Test func duplicateWordAcrossGroupsResolvesDeterministically() {
        for _ in 0..<8 {
            let compiled = Self.compile(
                Keywords(["keyword": "shared", "literal": "shared"]),
                caseInsensitive: false
            )
            #expect(compiled["shared"]?.scope == "literal")
        }
    }
}
