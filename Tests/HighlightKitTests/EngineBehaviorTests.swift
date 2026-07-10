import Foundation
import Testing
@testable import HighlightKit

@Suite("Engine behavior")
struct EngineBehaviorTests {
    @Test func unknownLanguageFallsBackToPlain() {
        let result = Highlighter.shared.highlight("hello", as: "definitely-not-a-language")
        #expect(result.language == nil)
        #expect(result.tokens.isEmpty)
        #expect(!result.illegal)
    }

    @Test func languageNamesAreCaseInsensitiveAndAliased() {
        #expect(Highlighter.shared.hasLanguage(named: "JSON"))
        #expect(Highlighter.shared.hasLanguage(named: "js"))
        #expect(Highlighter.shared.hasLanguage(named: "HTML"))
        #expect(!Highlighter.shared.hasLanguage(named: "nope"))
        let result = Highlighter.shared.highlight("var x = 1", as: "JS")
        #expect(result.language == "javascript")
    }

    @Test func illegalInputAbortsWhenRequested() {
        // `@` is illegal in pure JSON
        let bad = "{\"a\": @}"
        let honored = Highlighter.shared.highlight(bad, as: "json", ignoreIllegals: false)
        #expect(honored.illegal)
        #expect(honored.tokens.isEmpty)
        #expect(honored.relevance == 0)

        let ignored = Highlighter.shared.highlight(bad, as: "json", ignoreIllegals: true)
        #expect(!ignored.illegal)
        #expect(!ignored.tokens.isEmpty)
    }

    @Test func autoDetectPrefersTheObviousLanguage() {
        let json = #"{"key": [1, 2, 3], "flag": true}"#
        let result = Highlighter.shared.highlightAuto(json)
        #expect(result.language == "json")
        #expect(result.secondBest != nil)

        let xml = "<?xml version=\"1.0\"?><root attr=\"x\"><child/></root>"
        #expect(Highlighter.shared.highlightAuto(xml).language == "xml")
    }

    @Test func autoDetectRespectsSubset() {
        let code = #"{"a": 1}"#
        let result = Highlighter.shared.highlightAuto(code, subset: ["xml", "css"])
        #expect(result.language != "json")
    }

    @Test func xmlMayDelegateAStrictlySmallerSliceBackToItself() {
        let code = "<script><b></script>"
        let result = Highlighter.shared.highlight(code, as: "xml")

        #expect(result.relevance == 4)
        #expect(result.tokens == [
            HighlightToken(range: NSRange(location: 0, length: 1), scopes: ["tag"]),
            HighlightToken(range: NSRange(location: 1, length: 6), scopes: ["tag", "name"]),
            HighlightToken(range: NSRange(location: 7, length: 2), scopes: ["tag"]),
            HighlightToken(range: NSRange(location: 9, length: 1), scopes: ["tag", "name"]),
            HighlightToken(range: NSRange(location: 10, length: 3), scopes: ["tag"]),
            HighlightToken(range: NSRange(location: 13, length: 6), scopes: ["tag", "name"]),
            HighlightToken(range: NSRange(location: 19, length: 1), scopes: ["tag"]),
        ])
    }

    @Test func incrementalXMLMayAutoDetectAnEqualSizedNestedChunk() throws {
        let first = Highlighter.shared.highlight("<script>\n", as: "xml")
        let continuation = try #require(first.continuation)
        let nested = Highlighter.shared.highlight(
            "<b>\n",
            as: "xml",
            continuation: continuation
        )

        #expect(nested.relevance == 1)
        #expect(nested.tokens == [
            HighlightToken(range: NSRange(location: 0, length: 1), scopes: ["tag"]),
            HighlightToken(range: NSRange(location: 1, length: 1), scopes: ["tag", "name"]),
            HighlightToken(range: NSRange(location: 2, length: 1), scopes: ["tag"]),
        ])
    }

    @Test func continuationCarriesStateAcrossLines() {
        // Highlight a multi-line comment line by line; the comment state
        // must carry over via the continuation.
        let line1 = "/* start of comment\n"
        let line2 = "still inside */ 42\n"

        let first = Highlighter.shared.highlight(line1, as: "javascript")
        let second = Highlighter.shared.highlight(
            line2, as: "javascript", continuation: first.continuation
        )

        let ns2 = line2 as NSString
        let secondScopes = second.tokens.map { ($0.scope, ns2.substring(with: $0.range)) }
        // "still inside */" must be a comment; 42 a number
        #expect(secondScopes.contains { $0.0 == "comment" && $0.1.contains("still inside") })
        #expect(secondScopes.contains { $0.0 == "number" && $0.1 == "42" })

        // whole-string highlight agrees on scopes at the same offsets
        let whole = Highlighter.shared.highlight(line1 + line2, as: "javascript")
        let nsWhole = (line1 + line2) as NSString
        #expect(whole.tokens.contains { $0.scope == "number" && nsWhole.substring(with: $0.range) == "42" })
    }

    @Test func tokensNeverOverlapAndStayInBounds() {
        let samples: [(String, String)] = [
            ("json", #"{"a": [1, true, "x"], "b": {"c": null}}"#),
            ("xml", "<a href='x'>&amp;<b/></a>"),
            ("css", "a.cls { color: #fff; margin: 4px 2em }"),
            ("javascript", "const f = async (x) => `v=${x + 1}`;"),
        ]
        for (lang, code) in samples {
            let result = Highlighter.shared.highlight(code, as: lang)
            let length = (code as NSString).length
            var previousEnd = 0
            for token in result.tokens {
                #expect(token.range.location >= previousEnd, "overlap in \(lang)")
                #expect(token.range.length > 0)
                #expect(token.range.location + token.range.length <= length)
                previousEnd = token.range.location + token.range.length
            }
        }
    }

    @Test func unterminatedCSSSelectorsNeverEmitSyntheticEOFTokens() {
        for language in ["css", "less", "scss", "stylus"] {
            for code in ["[", "[abc", "[]", "[a]"] {
                let result = Highlighter.shared.highlight(code, as: language)
                let sourceLength = (code as NSString).length
                for token in result.tokens {
                    #expect(token.range.location >= 0)
                    #expect(token.range.length > 0)
                    #expect(token.range.location <= sourceLength)
                    #expect(token.range.length <= sourceLength - token.range.location)
                }
            }
        }
    }

    @Test func emojiAndCJKOffsetsAreUTF16() {
        // Emoji are 2 UTF-16 units; token ranges must be NSString-compatible.
        let code = #"{"名前😀": "值🎉"}"#
        let result = Highlighter.shared.highlight(code, as: "json")
        let ns = code as NSString
        let attr = result.tokens.first { $0.scope == "attr" }
        #expect(attr != nil)
        if let attr {
            #expect(ns.substring(with: attr.range) == "\"名前😀\"")
        }
        // rendering an attributed string must not crash and covers everything
        let attributed = result.attributedString(for: code, theme: .githubLight)
        #expect(attributed.length == ns.length)
    }

    @Test func registeringACustomLanguageWorks() {
        let custom = LanguageDescriptor(name: "shout") {
            LanguageDefinition(
                name: "shout",
                root: Mode(contains: [Mode(scope: "strong", begin: "[A-Z]{2,}")])
            )
        }
        let highlighter = Highlighter(languages: [custom])
        let result = highlighter.highlight("hello WORLD", as: "shout")
        #expect(result.tokens.count == 1)
        #expect(result.tokens[0].scope == "strong")
        #expect(result.tokens[0].range == NSRange(location: 6, length: 5))
    }

    @Test func highlighterIsUsableConcurrently() async {
        let codes = [
            #"{"a": 1}"#,
            "<a>x</a>",
            "body { color: red }",
            "const x = () => 1;",
        ]
        let langs = ["json", "xml", "css", "javascript"]
        await withTaskGroup(of: Int.self) { group in
            for i in 0..<32 {
                group.addTask {
                    let result = Highlighter.shared.highlight(codes[i % 4], as: langs[i % 4])
                    return result.tokens.count
                }
            }
            var total = 0
            for await count in group { total += count }
            #expect(total > 0)
        }
    }
}
